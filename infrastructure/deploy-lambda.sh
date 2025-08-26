#!/bin/bash

# Lambda Function Deployment Script
# This script packages and deploys the Lambda function code

set -e

# Configuration
STACK_NAME="cross-partition-inference-mvp"
REGION="us-gov-west-1"
PROFILE="govcloud"
LAMBDA_DIR="../lambda"
PACKAGE_FILE="lambda-deployment-package.zip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}📦 Lambda Function Deployment${NC}"
echo "=================================="
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name $STACK_NAME --profile $PROFILE --region $REGION > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Stack '$STACK_NAME' not found${NC}"
    echo "Please deploy the infrastructure first using deploy.sh"
    exit 1
fi

# Get Lambda function names from stack outputs
LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`LambdaFunctionName`].OutputValue' \
    --output text)

DASHBOARD_LAMBDA_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardLambdaFunctionName`].OutputValue' \
    --output text)

echo "Main Lambda Function: $LAMBDA_FUNCTION"
echo "Dashboard Lambda Function: $DASHBOARD_LAMBDA_FUNCTION"
echo ""

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Copy Lambda code to temp directory
cp -r $LAMBDA_DIR/* $TEMP_DIR/

# Install Python dependencies
echo -e "${YELLOW}📥 Installing Python dependencies...${NC}"
cd $TEMP_DIR
pip3 install -r requirements.txt -t . --quiet

# Remove unnecessary files
rm -f requirements.txt
rm -f test_lambda.py
rm -f README.md

# Create deployment package
echo -e "${YELLOW}📦 Creating deployment package...${NC}"
zip -r $PACKAGE_FILE . -q

# Deploy main Lambda function
echo -e "${YELLOW}🚀 Deploying main Lambda function...${NC}"
aws lambda update-function-code \
    --function-name $LAMBDA_FUNCTION \
    --zip-file fileb://$PACKAGE_FILE \
    --profile $PROFILE \
    --region $REGION > /dev/null

echo -e "${GREEN}✅ Main Lambda function deployed successfully${NC}"

# Create dashboard Lambda package (just the inline code is sufficient for now)
echo -e "${GREEN}✅ Dashboard Lambda function already deployed with CloudFormation${NC}"

# Cleanup
cd - > /dev/null
rm -rf $TEMP_DIR

echo ""
echo -e "${GREEN}🎉 Lambda deployment completed!${NC}"
echo ""
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo "1. Update commercial credentials in Secrets Manager"
echo "2. Test the API endpoints"

# Show API endpoints
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

echo ""
echo -e "${GREEN}🔗 API Endpoints:${NC}"
echo "API Gateway Base URL: $API_URL"
echo "Bedrock Proxy: $BEDROCK_ENDPOINT"
echo "Dashboard API: $DASHBOARD_ENDPOINT"