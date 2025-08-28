#!/bin/bash

# Test script for the Bedrock models discovery endpoint
# This script tests the new /bedrock/models endpoint

set -e

# Configuration
STACK_NAME="cross-partition-inference-mvp"
REGION="us-gov-west-1"
PROFILE="govcloud"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 Testing Bedrock Models Discovery Endpoint${NC}"
echo "=================================================="

# Get the API Gateway URL from CloudFormation
echo -e "${YELLOW}📝 Getting API Gateway URL...${NC}"
API_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text)

if [ -z "$API_URL" ]; then
    echo -e "${RED}❌ Could not retrieve API Gateway URL${NC}"
    exit 1
fi

MODELS_ENDPOINT="$API_URL/bedrock/models"
echo -e "${GREEN}✅ Models endpoint: $MODELS_ENDPOINT${NC}"

# Test the models endpoint
echo -e "${YELLOW}🚀 Testing models endpoint...${NC}"

# Get AWS credentials for signing the request
AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile $PROFILE)
AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile $PROFILE)
AWS_SESSION_TOKEN=$(aws configure get aws_session_token --profile $PROFILE)

# Use AWS CLI to make the signed request
echo -e "${YELLOW}📡 Making signed request to models endpoint...${NC}"

# Create a temporary file for the response
RESPONSE_FILE=$(mktemp)

# Make the request using aws cli with proper IAM signing
aws apigateway test-invoke-method \
    --rest-api-id $(echo $API_URL | cut -d'.' -f1 | cut -d'/' -f3) \
    --resource-id $(aws apigateway get-resources \
        --rest-api-id $(echo $API_URL | cut -d'.' -f1 | cut -d'/' -f3) \
        --profile $PROFILE \
        --region $REGION \
        --query 'items[?pathPart==`models`].id' \
        --output text) \
    --http-method GET \
    --profile $PROFILE \
    --region $REGION > $RESPONSE_FILE 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Request successful!${NC}"
    echo ""
    echo "Response:"
    echo "========="
    cat $RESPONSE_FILE | jq '.body' -r | jq '.' 2>/dev/null || cat $RESPONSE_FILE
else
    echo -e "${RED}❌ Request failed${NC}"
    echo "Error details:"
    cat $RESPONSE_FILE
fi

# Alternative test using curl (if the endpoint allows public access)
echo ""
echo -e "${YELLOW}🔄 Alternative test using direct HTTP request...${NC}"

# Try a direct curl request (this might fail due to IAM auth requirements)
curl -s -X GET "$MODELS_ENDPOINT" \
    -H "Content-Type: application/json" \
    -w "\nHTTP Status: %{http_code}\n" || echo -e "${YELLOW}⚠️  Direct HTTP request failed (expected if IAM auth is required)${NC}"

# Clean up
rm -f $RESPONSE_FILE

echo ""
echo -e "${GREEN}📋 Test Summary${NC}"
echo "==============="
echo "Endpoint: $MODELS_ENDPOINT"
echo "Expected response: JSON with available Bedrock models from us-east-1"
echo "Authentication: AWS IAM (signed requests required)"
echo ""
echo -e "${YELLOW}💡 To test with proper authentication, use:${NC}"
echo "aws apigateway test-invoke-method --rest-api-id <API_ID> --resource-id <RESOURCE_ID> --http-method GET --profile $PROFILE --region $REGION"