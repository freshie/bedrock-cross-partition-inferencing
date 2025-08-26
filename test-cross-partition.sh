#!/bin/bash

# Cross-Partition Inference Testing Script
# This script tests the deployed MVP solution

set -e

# Configuration
PROFILE="govcloud"
REGION="us-gov-west-1"
STACK_NAME="cross-partition-inference-mvp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Cross-Partition Inference Testing${NC}"
echo "===================================="
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --profile $PROFILE --region $REGION > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Stack '$STACK_NAME' not found${NC}"
    echo "Please deploy the MVP first using ./deploy-mvp.sh"
    exit 1
fi

# Get endpoints from stack
echo -e "${YELLOW}📡 Getting API endpoints...${NC}"

API_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text)

BEDROCK_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`BedrockEndpoint`].OutputValue' \
    --output text)

DASHBOARD_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardApiEndpoint`].OutputValue' \
    --output text)

echo "API Gateway: $API_URL"
echo "Bedrock Proxy: $BEDROCK_ENDPOINT"
echo "Dashboard API: $DASHBOARD_ENDPOINT"
echo ""

# Test 1: Dashboard API
echo -e "${BLUE}Test 1: Dashboard API Connectivity${NC}"
echo "=================================="

echo -e "${YELLOW}Testing GET $DASHBOARD_ENDPOINT${NC}"

if RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "$DASHBOARD_ENDPOINT"); then
    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✅ Dashboard API test passed (HTTP $HTTP_CODE)${NC}"
        
        # Parse response to show request count
        if command -v jq &> /dev/null; then
            REQUEST_COUNT=$(echo "$BODY" | jq -r '.requests | length' 2>/dev/null || echo "unknown")
            echo "Current requests in database: $REQUEST_COUNT"
        fi
    else
        echo -e "${YELLOW}⚠️  Dashboard API returned HTTP $HTTP_CODE${NC}"
        echo "Response: $BODY"
    fi
else
    echo -e "${RED}❌ Dashboard API test failed${NC}"
fi

echo ""

# Test 2: Bedrock Proxy (requires IAM authentication)
echo -e "${BLUE}Test 2: Bedrock Proxy Authentication${NC}"
echo "==================================="

echo -e "${YELLOW}Testing POST $BEDROCK_ENDPOINT${NC}"

# Create test payload
TEST_PAYLOAD='{
    "modelId": "anthropic.claude-3-haiku-20240307-v1:0",
    "contentType": "application/json",
    "accept": "application/json",
    "body": "{\"messages\":[{\"role\":\"user\",\"content\":\"Hello, this is a test from GovCloud!\"}],\"max_tokens\":100}"
}'

# Test with AWS CLI (which handles IAM authentication)
echo "Creating temporary test file..."
echo "$TEST_PAYLOAD" > test-payload.json

# Extract API ID and resource ID for testing
API_ID=$(echo "$BEDROCK_ENDPOINT" | sed 's/https:\/\/\([^.]*\).*/\1/')

echo "API ID: $API_ID"
echo ""

# Use AWS API Gateway test-invoke-method for testing
echo -e "${YELLOW}Testing with AWS API Gateway test-invoke-method...${NC}"

if aws apigateway get-rest-apis --profile $PROFILE --region $REGION > /dev/null 2>&1; then
    # Get resource ID for /bedrock/invoke-model
    RESOURCE_ID=$(aws apigateway get-resources \
        --rest-api-id $API_ID \
        --profile $PROFILE \
        --region $REGION \
        --query 'items[?pathPart==`invoke-model`].id' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$RESOURCE_ID" ]; then
        echo "Resource ID: $RESOURCE_ID"
        echo ""
        
        # Test the API Gateway method
        if TEST_RESULT=$(aws apigateway test-invoke-method \
            --rest-api-id $API_ID \
            --resource-id $RESOURCE_ID \
            --http-method POST \
            --body file://test-payload.json \
            --profile $PROFILE \
            --region $REGION 2>&1); then
            
            echo -e "${GREEN}✅ API Gateway method test completed${NC}"
            
            # Parse the result
            if command -v jq &> /dev/null; then
                STATUS=$(echo "$TEST_RESULT" | jq -r '.status' 2>/dev/null || echo "unknown")
                echo "Response Status: $STATUS"
                
                if [ "$STATUS" = "200" ]; then
                    echo -e "${GREEN}✅ Bedrock proxy test passed!${NC}"
                    echo "This indicates the Lambda function is working correctly."
                elif [ "$STATUS" = "500" ]; then
                    echo -e "${YELLOW}⚠️  Lambda function returned error (likely credential issue)${NC}"
                    echo "Check CloudWatch logs for details."
                else
                    echo -e "${YELLOW}⚠️  Unexpected status: $STATUS${NC}"
                fi
            fi
            
            echo ""
            echo "Full test result:"
            echo "$TEST_RESULT" | jq '.' 2>/dev/null || echo "$TEST_RESULT"
        else
            echo -e "${RED}❌ API Gateway test failed${NC}"
            echo "$TEST_RESULT"
        fi
    else
        echo -e "${YELLOW}⚠️  Could not find invoke-model resource${NC}"
    fi
else
    echo -e "${RED}❌ Cannot access API Gateway (insufficient permissions)${NC}"
fi

# Cleanup
rm -f test-payload.json

echo ""

# Test 3: Check CloudWatch Logs
echo -e "${BLUE}Test 3: CloudWatch Logs${NC}"
echo "======================="

LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

echo "Lambda Function: $LAMBDA_FUNCTION"

LOG_GROUP="/aws/lambda/$LAMBDA_FUNCTION"

echo -e "${YELLOW}Checking CloudWatch logs for $LOG_GROUP...${NC}"

if aws logs describe-log-groups \
    --log-group-name-prefix "$LOG_GROUP" \
    --profile $PROFILE \
    --region $REGION > /dev/null 2>&1; then
    
    echo -e "${GREEN}✅ CloudWatch log group exists${NC}"
    
    # Get recent log events
    if RECENT_LOGS=$(aws logs describe-log-streams \
        --log-group-name "$LOG_GROUP" \
        --order-by LastEventTime \
        --descending \
        --max-items 1 \
        --profile $PROFILE \
        --region $REGION 2>/dev/null); then
        
        LATEST_STREAM=$(echo "$RECENT_LOGS" | jq -r '.logStreams[0].logStreamName' 2>/dev/null)
        
        if [ "$LATEST_STREAM" != "null" ] && [ -n "$LATEST_STREAM" ]; then
            echo "Latest log stream: $LATEST_STREAM"
            
            echo -e "${YELLOW}Recent log events:${NC}"
            aws logs get-log-events \
                --log-group-name "$LOG_GROUP" \
                --log-stream-name "$LATEST_STREAM" \
                --limit 5 \
                --profile $PROFILE \
                --region $REGION \
                --query 'events[*].message' \
                --output text 2>/dev/null || echo "No recent events"
        else
            echo "No log streams found (function may not have been invoked yet)"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  CloudWatch log group not found or inaccessible${NC}"
fi

echo ""

# Test 4: DynamoDB Table
echo -e "${BLUE}Test 4: DynamoDB Request Logs${NC}"
echo "============================="

TABLE_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`DynamoDBTableName`].OutputValue' \
    --output text)

echo "DynamoDB Table: $TABLE_NAME"

echo -e "${YELLOW}Checking DynamoDB table...${NC}"

if aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --profile $PROFILE \
    --region $REGION > /dev/null 2>&1; then
    
    echo -e "${GREEN}✅ DynamoDB table exists${NC}"
    
    # Get item count
    if ITEM_COUNT=$(aws dynamodb scan \
        --table-name "$TABLE_NAME" \
        --select COUNT \
        --profile $PROFILE \
        --region $REGION \
        --query 'Count' \
        --output text 2>/dev/null); then
        
        echo "Total requests logged: $ITEM_COUNT"
        
        if [ "$ITEM_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✅ Request logs found in DynamoDB${NC}"
        else
            echo -e "${YELLOW}⚠️  No requests logged yet${NC}"
        fi
    fi
else
    echo -e "${RED}❌ DynamoDB table not accessible${NC}"
fi

echo ""

# Test 5: Website Accessibility
echo -e "${BLUE}Test 5: Website Accessibility${NC}"
echo "============================="

# Find the website bucket
BUCKET_NAME=$(aws s3api list-buckets --profile $PROFILE --region $REGION --query 'Buckets[?contains(Name, `cross-partition-dashboard`)].Name' --output text | head -1)

if [ -n "$BUCKET_NAME" ]; then
    WEBSITE_URL="http://$BUCKET_NAME.s3-website.us-gov-west-1.amazonaws.com"
    echo "Website URL: $WEBSITE_URL"
    
    echo -e "${YELLOW}Testing website accessibility...${NC}"
    
    if curl -s -f "$WEBSITE_URL" > /dev/null; then
        echo -e "${GREEN}✅ Website is accessible${NC}"
    else
        echo -e "${YELLOW}⚠️  Website accessibility test failed${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Website bucket not found${NC}"
fi

echo ""

# Summary
echo -e "${BLUE}🏁 Test Summary${NC}"
echo "==============="
echo ""
echo -e "${GREEN}✅ Tests completed!${NC}"
echo ""
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo "1. If tests passed, your MVP is working correctly"
echo "2. Open the dashboard website to monitor requests"
echo "3. Make actual cross-partition requests to see data flow"
echo "4. Check CloudWatch logs for detailed debugging"
echo ""
echo -e "${YELLOW}🔧 Troubleshooting:${NC}"
echo "• If Bedrock proxy fails: Check commercial credentials in Secrets Manager"
echo "• If dashboard shows no data: Make some test requests first"
echo "• If website is inaccessible: Check S3 bucket policy and configuration"
echo ""
echo -e "${GREEN}🎉 MVP Testing Complete!${NC}"