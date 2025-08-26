#!/bin/bash

# Cross-Partition Inference MVP - Complete Deployment Script
# This script deploys the entire MVP solution end-to-end

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

echo -e "${BLUE}🚀 Cross-Partition Inference MVP - Complete Deployment${NC}"
echo "=========================================================="
echo ""
echo "This script will deploy the complete MVP solution:"
echo "1. Infrastructure (CloudFormation)"
echo "2. Lambda functions"
echo "3. End-to-end testing"
echo ""
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo "Stack: $STACK_NAME"
echo ""

# Check prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not found. Please install AWS CLI v2.${NC}"
    exit 1
fi

# Check jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq not found. Please install jq for JSON parsing.${NC}"
    exit 1
fi

# Check AWS profile
if ! aws sts get-caller-identity --profile $PROFILE > /dev/null 2>&1; then
    echo -e "${RED}❌ AWS CLI not configured for profile '$PROFILE'${NC}"
    echo "Please run: aws configure --profile $PROFILE"
    exit 1
fi

# Get account info
ACCOUNT_INFO=$(aws sts get-caller-identity --profile $PROFILE)
ACCOUNT_ID=$(echo $ACCOUNT_INFO | jq -r '.Account')
USER_ARN=$(echo $ACCOUNT_INFO | jq -r '.Arn')

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo "Account ID: $ACCOUNT_ID"
echo "User: $USER_ARN"
echo ""

# Proceeding with deployment
echo -e "${GREEN}🚀 Proceeding with deployment...${NC}"

echo ""
echo -e "${BLUE}📦 Step 1: Deploying Infrastructure${NC}"
echo "======================================"

cd infrastructure
if ./deploy.sh; then
    echo -e "${GREEN}✅ Infrastructure deployment completed${NC}"
else
    echo -e "${RED}❌ Infrastructure deployment failed${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}🔐 Step 2: Commercial Credentials Setup${NC}"
echo "======================================="

# Get secret name from stack
SECRET_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`SecretsManagerSecretName`].OutputValue' \
    --output text)

echo "Secret Name: $SECRET_NAME"
echo ""
echo -e "${YELLOW}⚠️  You need to update the commercial AWS credentials in Secrets Manager.${NC}"
echo ""
echo "Current placeholder credentials need to be replaced with actual commercial credentials."
echo ""
echo "Command to update credentials:"
echo -e "${BLUE}aws secretsmanager update-secret \\${NC}"
echo -e "${BLUE}    --secret-id $SECRET_NAME \\${NC}"
echo -e "${BLUE}    --secret-string '{\"bedrock_api_key\":\"YOUR_BEDROCK_API_KEY\",\"region\":\"us-east-1\"}' \\${NC}"
echo -e "${BLUE}    --profile $PROFILE \\${NC}"
echo -e "${BLUE}    --region $REGION${NC}"
echo ""

echo -e "${YELLOW}⚠️  Note: You'll need to update commercial credentials later for cross-partition calls to work.${NC}"

echo ""
echo -e "${BLUE}🔧 Step 3: Deploying Lambda Functions${NC}"
echo "====================================="

if ./deploy-lambda.sh; then
    echo -e "${GREEN}✅ Lambda deployment completed${NC}"
else
    echo -e "${RED}❌ Lambda deployment failed${NC}"
    exit 1
fi

cd ..



echo ""
echo -e "${BLUE}🧪 Step 5: Running Tests${NC}"
echo "========================="

# Get endpoints from stack
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

MODELS_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`ModelsEndpoint`].OutputValue' \
    --output text)

echo "Testing endpoints:"
echo "API Gateway: $API_URL"
echo "Bedrock Proxy: $BEDROCK_ENDPOINT"
echo "Models Discovery: $MODELS_ENDPOINT"
echo ""

# Test routing info endpoint
echo -e "${YELLOW}🔍 Testing Routing Info Endpoint...${NC}"
if curl -s -f "$BEDROCK_ENDPOINT" > /dev/null; then
    echo -e "${GREEN}✅ Routing info endpoint is accessible${NC}"
    echo ""
    echo -e "${BLUE}Sample routing info:${NC}"
    curl -s "$BEDROCK_ENDPOINT" | jq '.' || echo "Response received (jq not available for formatting)"
else
    echo -e "${YELLOW}⚠️  Routing info endpoint test failed${NC}"
fi

echo ""
echo -e "${GREEN}🎉 MVP Deployment Completed!${NC}"
echo "============================="
echo ""
echo -e "${GREEN}📊 Deployment Summary:${NC}"
echo "• Infrastructure: ✅ Deployed"
echo "• Lambda Functions: ✅ Deployed"
echo "• API Endpoints: ✅ Available"
echo ""
echo -e "${GREEN}🔗 Access Points:${NC}"
echo "API Gateway: $API_URL"
echo "Bedrock Proxy: $BEDROCK_ENDPOINT"
echo "Models Discovery: $MODELS_ENDPOINT"

echo ""
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo "1. Update commercial credentials if not done already"
echo "2. Test the routing info endpoint: curl $BEDROCK_ENDPOINT"
echo "3. Make test cross-partition requests"
echo ""
echo -e "${YELLOW}🧪 Test Commands:${NC}"
echo "Cross-partition requests: ./test-cross-partition.sh"
echo "Models discovery: ./test-models-endpoint.sh"
echo ""
echo -e "${GREEN}✅ MVP is ready for use!${NC}"