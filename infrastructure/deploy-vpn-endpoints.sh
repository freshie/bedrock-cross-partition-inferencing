#!/bin/bash

# Deploy VPC endpoints for VPN connectivity
# This script deploys VPC endpoints in both GovCloud and Commercial partitions

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

echo -e "${GREEN}🚀 Deploying VPC endpoints for VPN connectivity${NC}"
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

# Function to check if VPC stack exists
check_vpc_stack() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    
    echo -e "${YELLOW}🔍 Checking if $partition VPC stack exists: $stack_name${NC}"
    
    if ! aws cloudformation describe-stacks \
        --profile "$profile" \
        --stack-name "$stack_name" \
        --query 'Stacks[0].StackStatus' \
        --output text >/dev/null 2>&1; then
        echo -e "${RED}❌ $partition VPC stack '$stack_name' not found${NC}"
        echo "Please deploy the VPC stack first using: ./deploy-vpn-vpc.sh"
        exit 1
    fi
    
    echo -e "${GREEN}✅ $partition VPC stack found${NC}"
}

# Function to deploy CloudFormation stack
deploy_stack() {
    local profile=$1
    local stack_name=$2
    local template_file=$3
    local partition=$4
    local vpc_stack_name=$5
    
    echo -e "${YELLOW}📦 Deploying $partition VPC endpoints stack: $stack_name${NC}"
    
    aws cloudformation deploy \
        --profile "$profile" \
        --template-file "$template_file" \
        --stack-name "$stack_name" \
        --parameter-overrides \
            Environment="$ENVIRONMENT" \
            ProjectName="$PROJECT_NAME" \
            VPCStackName="$vpc_stack_name" \
        --capabilities CAPABILITY_IAM \
        --tags \
            Project="$PROJECT_NAME" \
            Environment="$ENVIRONMENT" \
            Partition="$partition" \
            Component="vpc-endpoints"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $partition VPC endpoints stack deployed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to deploy $partition VPC endpoints stack${NC}"
        exit 1
    fi
}

# Function to get stack outputs
get_stack_outputs() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    
    echo -e "${YELLOW}📋 Getting $partition VPC endpoints stack outputs${NC}"
    
    aws cloudformation describe-stacks \
        --profile "$profile" \
        --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
}

# Function to get VPC endpoint configuration
get_endpoint_config() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    
    echo -e "${YELLOW}🔧 Getting $partition VPC endpoint configuration${NC}"
    
    aws cloudformation describe-stacks \
        --profile "$profile" \
        --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs[?OutputKey==`VPCEndpointConfiguration`].OutputValue' \
        --output text
}

# Check prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites${NC}"
check_profile "$GOVCLOUD_PROFILE"
check_profile "$COMMERCIAL_PROFILE"

# Verify template files exist
if [ ! -f "vpn-govcloud-endpoints.yaml" ]; then
    echo -e "${RED}❌ GovCloud VPC endpoints template not found: vpn-govcloud-endpoints.yaml${NC}"
    exit 1
fi

if [ ! -f "vpn-commercial-endpoints.yaml" ]; then
    echo -e "${RED}❌ Commercial VPC endpoints template not found: vpn-commercial-endpoints.yaml${NC}"
    exit 1
fi

# Check if VPC stacks exist
GOVCLOUD_VPC_STACK_NAME="${PROJECT_NAME}-govcloud-vpc"
COMMERCIAL_VPC_STACK_NAME="${PROJECT_NAME}-commercial-vpc"

check_vpc_stack "$GOVCLOUD_PROFILE" "$GOVCLOUD_VPC_STACK_NAME" "GovCloud"
check_vpc_stack "$COMMERCIAL_PROFILE" "$COMMERCIAL_VPC_STACK_NAME" "Commercial"

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Deploy GovCloud VPC endpoints
GOVCLOUD_ENDPOINTS_STACK_NAME="${PROJECT_NAME}-govcloud-endpoints"
deploy_stack "$GOVCLOUD_PROFILE" "$GOVCLOUD_ENDPOINTS_STACK_NAME" "vpn-govcloud-endpoints.yaml" "GovCloud" "$GOVCLOUD_VPC_STACK_NAME"
echo ""

# Deploy Commercial VPC endpoints
COMMERCIAL_ENDPOINTS_STACK_NAME="${PROJECT_NAME}-commercial-endpoints"
deploy_stack "$COMMERCIAL_PROFILE" "$COMMERCIAL_ENDPOINTS_STACK_NAME" "vpn-commercial-endpoints.yaml" "Commercial" "$COMMERCIAL_VPC_STACK_NAME"
echo ""

# Display stack outputs
echo -e "${GREEN}🎉 VPC endpoints deployment completed successfully!${NC}"
echo ""
echo -e "${YELLOW}📊 Stack Outputs:${NC}"
echo ""
echo "=== GovCloud VPC Endpoints Stack Outputs ==="
get_stack_outputs "$GOVCLOUD_PROFILE" "$GOVCLOUD_ENDPOINTS_STACK_NAME" "GovCloud"
echo ""
echo "=== Commercial VPC Endpoints Stack Outputs ==="
get_stack_outputs "$COMMERCIAL_PROFILE" "$COMMERCIAL_ENDPOINTS_STACK_NAME" "Commercial"
echo ""

# Display endpoint configurations
echo -e "${YELLOW}🔧 VPC Endpoint Configurations:${NC}"
echo ""
echo "=== GovCloud VPC Endpoint Configuration ==="
get_endpoint_config "$GOVCLOUD_PROFILE" "$GOVCLOUD_ENDPOINTS_STACK_NAME" "GovCloud"
echo ""
echo "=== Commercial VPC Endpoint Configuration ==="
get_endpoint_config "$COMMERCIAL_PROFILE" "$COMMERCIAL_ENDPOINTS_STACK_NAME" "Commercial"
echo ""

echo -e "${GREEN}✅ Next steps:${NC}"
echo "1. Deploy VPN Gateway infrastructure using: ./deploy-vpn-gateway.sh"
echo "2. Update Lambda function for VPC deployment"
echo "3. Test VPC endpoint connectivity"
echo ""
echo -e "${YELLOW}💡 Note: All AWS services now accessible via private VPC endpoints${NC}"