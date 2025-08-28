#!/bin/bash

# Deploy VPC infrastructure for VPN connectivity
# This script deploys VPC infrastructure in both GovCloud and Commercial partitions

set -e

# Configuration
PROJECT_NAME="cross-partition-vpn"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying VPC infrastructure for VPN connectivity${NC}"
echo "Project: $PROJECT_NAME"
echo "Environment: $ENVIRONMENT"
echo ""

# Function to check if AWS CLI profile exists
check_profile() {
    local profile=$1
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo -e "${RED}❌ AWS CLI profile '$profile' not found${NC}"
        echo "Please configure the profile using: aws configure --profile $profile"
        exit 1
    fi
}

# Function to deploy CloudFormation stack
deploy_stack() {
    local profile=$1
    local stack_name=$2
    local template_file=$3
    local partition=$4
    
    echo -e "${YELLOW}📦 Deploying $partition VPC stack: $stack_name${NC}"
    
    aws cloudformation deploy \
        --profile "$profile" \
        --template-file "$template_file" \
        --stack-name "$stack_name" \
        --parameter-overrides \
            Environment="$ENVIRONMENT" \
            ProjectName="$PROJECT_NAME" \
        --capabilities CAPABILITY_IAM \
        --tags \
            Project="$PROJECT_NAME" \
            Environment="$ENVIRONMENT" \
            Partition="$partition" \
            Component="vpc-infrastructure"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $partition VPC stack deployed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to deploy $partition VPC stack${NC}"
        exit 1
    fi
}

# Function to get stack outputs
get_stack_outputs() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    
    echo -e "${YELLOW}📋 Getting $partition VPC stack outputs${NC}"
    
    aws cloudformation describe-stacks \
        --profile "$profile" \
        --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
}

# Check prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites${NC}"
check_profile "$GOVCLOUD_PROFILE"
check_profile "$COMMERCIAL_PROFILE"

# Verify template files exist
if [ ! -f "vpn-govcloud-vpc.yaml" ]; then
    echo -e "${RED}❌ GovCloud VPC template not found: vpn-govcloud-vpc.yaml${NC}"
    exit 1
fi

if [ ! -f "vpn-commercial-vpc.yaml" ]; then
    echo -e "${RED}❌ Commercial VPC template not found: vpn-commercial-vpc.yaml${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Deploy GovCloud VPC
GOVCLOUD_STACK_NAME="${PROJECT_NAME}-govcloud-vpc"
deploy_stack "$GOVCLOUD_PROFILE" "$GOVCLOUD_STACK_NAME" "vpn-govcloud-vpc.yaml" "GovCloud"
echo ""

# Deploy Commercial VPC
COMMERCIAL_STACK_NAME="${PROJECT_NAME}-commercial-vpc"
deploy_stack "$COMMERCIAL_PROFILE" "$COMMERCIAL_STACK_NAME" "vpn-commercial-vpc.yaml" "Commercial"
echo ""

# Display stack outputs
echo -e "${GREEN}🎉 VPC infrastructure deployment completed successfully!${NC}"
echo ""
echo -e "${YELLOW}📊 Stack Outputs:${NC}"
echo ""
echo "=== GovCloud VPC Stack Outputs ==="
get_stack_outputs "$GOVCLOUD_PROFILE" "$GOVCLOUD_STACK_NAME" "GovCloud"
echo ""
echo "=== Commercial VPC Stack Outputs ==="
get_stack_outputs "$COMMERCIAL_PROFILE" "$COMMERCIAL_STACK_NAME" "Commercial"
echo ""

echo -e "${GREEN}✅ Next steps:${NC}"
echo "1. Deploy VPC endpoints using: ./deploy-vpn-endpoints.sh"
echo "2. Deploy VPN Gateway infrastructure using: ./deploy-vpn-gateway.sh"
echo "3. Update Lambda function for VPC deployment"
echo ""
echo -e "${YELLOW}💡 Note: VPC infrastructure is now ready for VPN connectivity${NC}"