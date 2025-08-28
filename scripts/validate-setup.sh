#!/bin/bash

# Cross-Partition Inference Setup Validation
# This script validates that all prerequisites are met before deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Cross-Partition Inference Setup Validation${NC}"
echo "=============================================="
echo ""

VALIDATION_PASSED=true

# Check 1: AWS CLI
echo -e "${YELLOW}Checking AWS CLI...${NC}"
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    echo -e "${GREEN}✅ AWS CLI found (version $AWS_VERSION)${NC}"
else
    echo -e "${RED}❌ AWS CLI not found${NC}"
    echo "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    VALIDATION_PASSED=false
fi

# Check 2: jq
echo -e "${YELLOW}Checking jq...${NC}"
if command -v jq &> /dev/null; then
    JQ_VERSION=$(jq --version)
    echo -e "${GREEN}✅ jq found ($JQ_VERSION)${NC}"
else
    echo -e "${RED}❌ jq not found${NC}"
    echo "Please install jq: https://stedolan.github.io/jq/download/"
    VALIDATION_PASSED=false
fi

# Check 3: curl
echo -e "${YELLOW}Checking curl...${NC}"
if command -v curl &> /dev/null; then
    echo -e "${GREEN}✅ curl found${NC}"
else
    echo -e "${RED}❌ curl not found${NC}"
    echo "Please install curl"
    VALIDATION_PASSED=false
fi

# Check 4: GovCloud AWS Profile
echo -e "${YELLOW}Checking GovCloud AWS profile...${NC}"
if aws sts get-caller-identity --profile govcloud > /dev/null 2>&1; then
    ACCOUNT_INFO=$(aws sts get-caller-identity --profile govcloud)
    ACCOUNT_ID=$(echo $ACCOUNT_INFO | jq -r '.Account')
    USER_ARN=$(echo $ACCOUNT_INFO | jq -r '.Arn')
    
    echo -e "${GREEN}✅ GovCloud profile configured${NC}"
    echo "   Account ID: $ACCOUNT_ID"
    echo "   User: $USER_ARN"
    
    # Check if it's actually a GovCloud account
    if [[ $USER_ARN == *"aws-us-gov"* ]]; then
        echo -e "${GREEN}✅ Confirmed GovCloud account${NC}"
    else
        echo -e "${YELLOW}⚠️  Warning: This doesn't appear to be a GovCloud account${NC}"
        echo "   Expected ARN to contain 'aws-us-gov'"
    fi
else
    echo -e "${RED}❌ GovCloud AWS profile not configured${NC}"
    echo "Please run: aws configure --profile govcloud"
    VALIDATION_PASSED=false
fi

# Check 5: Required AWS Permissions
echo -e "${YELLOW}Checking AWS permissions...${NC}"
REQUIRED_PERMISSIONS=(
    "cloudformation:CreateStack"
    "cloudformation:UpdateStack"
    "cloudformation:DescribeStacks"
    "lambda:CreateFunction"
    "lambda:UpdateFunctionCode"
    "apigateway:GET"
    "s3:CreateBucket"
    "s3:PutObject"
    "dynamodb:CreateTable"
    "secretsmanager:CreateSecret"
    "iam:CreateRole"
    "iam:AttachRolePolicy"
)

# We can't easily test all permissions, but we can test a few key ones
if aws cloudformation list-stacks --profile govcloud --region us-gov-west-1 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ CloudFormation access confirmed${NC}"
else
    echo -e "${RED}❌ CloudFormation access denied${NC}"
    VALIDATION_PASSED=false
fi

if aws s3 ls --profile govcloud --region us-gov-west-1 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ S3 access confirmed${NC}"
else
    echo -e "${RED}❌ S3 access denied${NC}"
    VALIDATION_PASSED=false
fi

# Check 6: Commercial AWS Credentials Available
echo -e "${YELLOW}Checking commercial AWS credentials...${NC}"
echo "You will need commercial AWS credentials for cross-partition access."
echo "These should include:"
echo "  • AWS Access Key ID"
echo "  • AWS Secret Access Key"
echo "  • Access to Bedrock in us-east-1"
echo ""
echo -e "${GREEN}✅ Commercial credentials can be added during deployment${NC}"

# Check 7: File Structure
echo -e "${YELLOW}Checking project file structure...${NC}"
REQUIRED_FILES=(
    "scripts/deploy-over-internet.sh"
    "test-cross-partition.sh"
    "infrastructure/cross-partition-infrastructure.yaml"
    "infrastructure/deploy.sh"
    "infrastructure/deploy-lambda.sh"
    "lambda/lambda_function.py"
    "lambda/requirements.txt"
)

MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All required files present${NC}"
else
    echo -e "${RED}❌ Missing required files:${NC}"
    for file in "${MISSING_FILES[@]}"; do
        echo "   - $file"
    done
    VALIDATION_PASSED=false
fi

# Check 8: Script Permissions
echo -e "${YELLOW}Checking script permissions...${NC}"
SCRIPTS=(
    "scripts/deploy-over-internet.sh"
    "test-cross-partition.sh"
    "infrastructure/deploy.sh"
    "infrastructure/deploy-lambda.sh"
)

for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        echo -e "${GREEN}✅ $script is executable${NC}"
    elif [ -f "$script" ]; then
        echo -e "${YELLOW}⚠️  $script is not executable (fixing...)${NC}"
        chmod +x "$script"
        echo -e "${GREEN}✅ $script made executable${NC}"
    fi
done

echo ""
echo -e "${BLUE}📋 Validation Summary${NC}"
echo "===================="

if [ "$VALIDATION_PASSED" = true ]; then
    echo -e "${GREEN}🎉 All validations passed!${NC}"
    echo ""
    echo -e "${GREEN}✅ Ready for deployment${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Run: ./scripts/deploy-over-internet.sh (for internet routing) or ./scripts/deploy-complete-vpn-infrastructure.sh (for VPN routing)"
    echo "2. Follow the prompts to complete deployment"
    echo "3. Update commercial credentials when prompted"
    echo "4. Test with: ./test-cross-partition.sh"
    echo ""
else
    echo -e "${RED}❌ Validation failed${NC}"
    echo ""
    echo -e "${YELLOW}Please fix the issues above before proceeding with deployment.${NC}"
    echo ""
fi

echo -e "${BLUE}📚 Documentation:${NC}"
echo "• Project overview: README.md"
echo "• Infrastructure: infrastructure/README.md"
echo "• Lambda functions: lambda/README.md"
echo "• AWS profiles: aws-profile-guide.md"
echo ""

if [ "$VALIDATION_PASSED" = true ]; then
    exit 0
else
    exit 1
fi