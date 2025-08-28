#!/bin/bash

# Helper script to extract configuration from deployed CloudFormation stack
# This script creates a config.sh file from your deployed infrastructure

set -e

# Default values
STACK_NAME="${STACK_NAME:-cross-partition-inference-mvp}"
PROFILE="${AWS_PROFILE:-govcloud}"
REGION="${AWS_REGION:-us-gov-west-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Extracting Configuration from CloudFormation Stack${NC}"
echo "=================================================="
echo ""

# Check if stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --profile "$PROFILE" --region "$REGION" > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Stack '$STACK_NAME' not found${NC}"
    echo -e "${YELLOW}Available options:${NC}"
    echo "1. Deploy the infrastructure first: ./scripts/deploy-over-internet.sh (internet) or ./scripts/deploy-complete-vpn-infrastructure.sh (VPN)"
    echo "2. Use a different stack name: STACK_NAME=your-stack-name $0"
    echo "3. Use a different profile: AWS_PROFILE=your-profile $0"
    exit 1
fi

echo -e "${YELLOW}📡 Getting configuration from stack: $STACK_NAME${NC}"

# Extract outputs from CloudFormation
API_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
    --output text)

BEDROCK_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`BedrockEndpoint`].OutputValue' \
    --output text)

MODELS_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ModelsEndpoint`].OutputValue' \
    --output text)

SECRET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`SecretsManagerSecretName`].OutputValue' \
    --output text 2>/dev/null || echo "cross-partition-commercial-creds")

# Validate we got the required values
if [ -z "$API_URL" ]; then
    echo -e "${RED}❌ Could not extract API Gateway URL from stack${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Configuration extracted successfully:${NC}"
echo "   API Gateway URL: $API_URL"
echo "   Bedrock Endpoint: $BEDROCK_ENDPOINT"
echo "   Models Endpoint: $MODELS_ENDPOINT"
echo "   Secret Name: $SECRET_NAME"
echo ""

# Create config directory if it doesn't exist
mkdir -p config

# Create config.sh file
echo -e "${YELLOW}📝 Creating config/config.sh file...${NC}"

cat > config/config.sh << EOF
#!/bin/bash

# Cross-Partition Bedrock Inference Configuration
# Auto-generated from CloudFormation stack: $STACK_NAME
# Generated on: $(date)

# =============================================================================
# API Gateway Configuration (from CloudFormation)
# =============================================================================

# Your API Gateway base URL
export API_BASE_URL="$API_URL"

# Specific endpoints
export BEDROCK_ENDPOINT="$BEDROCK_ENDPOINT"
export MODELS_ENDPOINT="$MODELS_ENDPOINT"

# =============================================================================
# AWS Configuration
# =============================================================================

# AWS Region where your infrastructure is deployed
export AWS_REGION="$REGION"

# AWS Profile used for deployment
export AWS_PROFILE="$PROFILE"

# CloudFormation stack name
export STACK_NAME="$STACK_NAME"

# =============================================================================
# Security Configuration
# =============================================================================

# Secrets Manager secret name for Bedrock credentials
export BEDROCK_SECRET_NAME="$SECRET_NAME"

# =============================================================================
# Testing Configuration
# =============================================================================

# Model ID to use for testing
export TEST_MODEL_ID="anthropic.claude-3-5-sonnet-20241022-v2:0"

# Maximum tokens for test requests
export TEST_MAX_TOKENS="1000"

# =============================================================================
# Auto-generated configuration
# =============================================================================
# This file was auto-generated from your deployed CloudFormation stack.
# To regenerate: ./scripts/get-config.sh
# To customize: Edit the values above as needed
EOF

chmod +x config/config.sh

echo -e "${GREEN}✅ Configuration file created: config/config.sh${NC}"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Review the generated config/config.sh file"
echo "2. Customize any values as needed"
echo "3. Source the config: source config/config.sh"
echo "4. Run your tests: ./test-invoke-model.sh"
echo ""
echo -e "${BLUE}🎉 Configuration extraction complete!${NC}"