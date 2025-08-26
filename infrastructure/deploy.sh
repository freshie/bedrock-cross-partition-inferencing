#!/bin/bash

# Cross-Partition Inference Infrastructure Deployment Script
# This script deploys the MVP infrastructure to AWS GovCloud

set -e

# Configuration
STACK_NAME="cross-partition-inference-mvp"
TEMPLATE_FILE="cross-partition-infrastructure.yaml"
REGION="us-gov-west-1"
PROFILE="govcloud"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Cross-Partition Inference MVP Deployment${NC}"
echo "=================================================="
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "Profile: $PROFILE"
echo ""

# Check if AWS CLI is configured
if ! aws sts get-caller-identity --profile $PROFILE > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: AWS CLI not configured for profile '$PROFILE'${NC}"
    echo "Please run: aws configure --profile $PROFILE"
    exit 1
fi

# Get current AWS account info
ACCOUNT_INFO=$(aws sts get-caller-identity --profile $PROFILE)
ACCOUNT_ID=$(echo $ACCOUNT_INFO | jq -r '.Account')
USER_ARN=$(echo $ACCOUNT_INFO | jq -r '.Arn')

echo -e "${GREEN}✅ AWS Profile configured${NC}"
echo "Account ID: $ACCOUNT_ID"
echo "User: $USER_ARN"
echo ""

# Check if stack already exists
if aws cloudformation describe-stacks --stack-name $STACK_NAME --profile $PROFILE --region $REGION > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Stack '$STACK_NAME' already exists. Updating...${NC}"
    OPERATION="update-stack"
else
    echo -e "${GREEN}📦 Creating new stack '$STACK_NAME'...${NC}"
    OPERATION="create-stack"
fi

# Deploy the CloudFormation stack
echo "Deploying CloudFormation template..."
aws cloudformation $OPERATION \
    --stack-name $STACK_NAME \
    --template-body file://$TEMPLATE_FILE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $PROFILE \
    --region $REGION \
    --tags Key=Purpose,Value=CrossPartitionInference Key=Environment,Value=MVP

echo -e "${GREEN}✅ CloudFormation deployment initiated${NC}"
echo ""

# Wait for stack deployment to complete
echo "Waiting for stack deployment to complete..."
aws cloudformation wait stack-${OPERATION%-stack}-complete \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION

# Check deployment status
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].StackStatus' \
    --output text)

if [[ $STACK_STATUS == *"COMPLETE"* ]]; then
    echo -e "${GREEN}🎉 Stack deployment completed successfully!${NC}"
    echo ""
    
    # Get stack outputs
    echo "Stack Outputs:"
    echo "=============="
    aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --profile $PROFILE \
        --region $REGION \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
    
    echo ""
    echo -e "${YELLOW}📝 Next Steps:${NC}"
    echo "1. Update the commercial credentials in Secrets Manager"
    echo "2. Deploy the Lambda function code"
    echo "3. Test the API endpoints"
    
    # Get the secret name for credential update
    SECRET_NAME=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --profile $PROFILE \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`SecretsManagerSecretName`].OutputValue' \
        --output text)
    
    echo ""
    echo -e "${YELLOW}🔐 To update commercial credentials:${NC}"
    echo "aws secretsmanager update-secret \\"
    echo "    --secret-id $SECRET_NAME \\"
    echo "    --secret-string '{\"aws_access_key_id\":\"YOUR_KEY\",\"aws_secret_access_key\":\"YOUR_SECRET\",\"region\":\"us-east-1\"}' \\"
    echo "    --profile $PROFILE \\"
    echo "    --region $REGION"
    
else
    echo -e "${RED}❌ Stack deployment failed with status: $STACK_STATUS${NC}"
    
    # Show stack events for debugging
    echo ""
    echo "Recent stack events:"
    aws cloudformation describe-stack-events \
        --stack-name $STACK_NAME \
        --profile $PROFILE \
        --region $REGION \
        --query 'StackEvents[0:10].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
        --output table
    
    exit 1
fi