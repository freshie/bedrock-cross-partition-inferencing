#!/bin/bash

# Deploy VPN Gateway infrastructure for cross-partition connectivity
# This script deploys VPN Gateway infrastructure in both GovCloud and Commercial partitions

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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying VPN Gateway infrastructure for cross-partition connectivity${NC}"
echo "Project: $PROJECT_NAME"
echo "Environment: $ENVIRONMENT"
echo ""

# Function to generate secure pre-shared key
generate_psk() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to check if AWS CLI profile exists
check_profile() {
    local profile=$1
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo -e "${RED}❌ AWS CLI profile '$profile' not found${NC}"
        echo "Please configure the profile using: aws configure --profile $profile"
        exit 1
    fi
}

# Function to check if required stacks exist
check_required_stacks() {
    local profile=$1
    local vpc_stack=$2
    local endpoints_stack=$3
    local partition=$4
    
    echo -e "${YELLOW}🔍 Checking required stacks for $partition${NC}"
    
    # Check VPC stack
    if ! aws cloudformation describe-stacks \
        --profile "$profile" \
        --stack-name "$vpc_stack" \
        --query 'Stacks[0].StackStatus' \
        --output text >/dev/null 2>&1; then
        echo -e "${RED}❌ $partition VPC stack '$vpc_stack' not found${NC}"
        echo "Please deploy the VPC stack first using: ./deploy-vpn-vpc.sh"
        exit 1
    fi
    
    # Check endpoints stack
    if ! aws cloudformation describe-stacks \
        --profile "$profile" \
        --stack-name "$endpoints_stack" \
        --query 'Stacks[0].StackStatus' \
        --output text >/dev/null 2>&1; then
        echo -e "${RED}❌ $partition VPC endpoints stack '$endpoints_stack' not found${NC}"
        echo "Please deploy the VPC endpoints stack first using: ./deploy-vpn-endpoints.sh"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Required stacks found for $partition${NC}"
}

# Function to get public IP for Customer Gateway
get_public_ip() {
    local profile=$1
    local partition=$2
    
    echo -e "${YELLOW}🌐 Getting public IP for $partition Customer Gateway${NC}"
    
    # For demo purposes, we'll use a placeholder IP
    # In real deployment, this would be the actual public IP of the remote partition's VPN endpoint
    if [ "$partition" == "GovCloud" ]; then
        echo "203.0.113.1"  # Example IP for GovCloud
    else
        echo "203.0.113.2"  # Example IP for Commercial
    fi
}

# Function to deploy VPN Gateway stack
deploy_vpn_gateway() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    local vpc_stack_name=$4
    local govcloud_ip=$5
    local commercial_ip=$6
    local tunnel1_psk=$7
    local tunnel2_psk=$8
    
    echo -e "${YELLOW}📦 Deploying $partition VPN Gateway stack: $stack_name${NC}"
    
    aws cloudformation deploy \
        --profile "$profile" \
        --template-file "vpn-gateway.yaml" \
        --stack-name "$stack_name" \
        --parameter-overrides \
            Environment="$ENVIRONMENT" \
            ProjectName="$PROJECT_NAME" \
            GovCloudVPCStackName="${PROJECT_NAME}-govcloud-vpc" \
            CommercialVPCStackName="${PROJECT_NAME}-commercial-vpc" \
            GovCloudCustomerGatewayIP="$govcloud_ip" \
            CommercialCustomerGatewayIP="$commercial_ip" \
            Tunnel1PreSharedKey="$tunnel1_psk" \
            Tunnel2PreSharedKey="$tunnel2_psk" \
            GovCloudBGPASN=65000 \
            CommercialBGPASN=65001 \
        --capabilities CAPABILITY_IAM \
        --tags \
            Project="$PROJECT_NAME" \
            Environment="$ENVIRONMENT" \
            Partition="$partition" \
            Component="vpn-gateway"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $partition VPN Gateway stack deployed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to deploy $partition VPN Gateway stack${NC}"
        exit 1
    fi
}

# Function to deploy VPN validation stack
deploy_vpn_validation() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    local vpc_stack_name=$4
    local vpn_gateway_stack_name=$5
    
    echo -e "${YELLOW}📦 Deploying $partition VPN validation stack: $stack_name${NC}"
    
    aws cloudformation deploy \
        --profile "$profile" \
        --template-file "vpn-connectivity-validation.yaml" \
        --stack-name "$stack_name" \
        --parameter-overrides \
            Environment="$ENVIRONMENT" \
            ProjectName="$PROJECT_NAME" \
            VPCStackName="$vpc_stack_name" \
            VPNGatewayStackName="$vpn_gateway_stack_name" \
        --capabilities CAPABILITY_IAM \
        --tags \
            Project="$PROJECT_NAME" \
            Environment="$ENVIRONMENT" \
            Partition="$partition" \
            Component="vpn-validation"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $partition VPN validation stack deployed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to deploy $partition VPN validation stack${NC}"
        exit 1
    fi
}

# Function to get stack outputs
get_stack_outputs() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    
    echo -e "${YELLOW}📋 Getting $partition VPN Gateway stack outputs${NC}"
    
    aws cloudformation describe-stacks \
        --profile "$profile" \
        --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
}

# Function to test VPN validation
test_vpn_validation() {
    local profile=$1
    local function_name=$2
    local partition=$3
    
    echo -e "${YELLOW}🧪 Testing VPN validation for $partition${NC}"
    
    aws lambda invoke \
        --profile "$profile" \
        --function-name "$function_name" \
        --payload '{}' \
        --cli-binary-format raw-in-base64-out \
        "/tmp/vpn-validation-${partition,,}.json"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ VPN validation test completed for $partition${NC}"
        echo "Results saved to: /tmp/vpn-validation-${partition,,}.json"
    else
        echo -e "${RED}❌ VPN validation test failed for $partition${NC}"
    fi
}

# Check prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites${NC}"
check_profile "$GOVCLOUD_PROFILE"
check_profile "$COMMERCIAL_PROFILE"

# Verify template files exist
if [ ! -f "vpn-gateway.yaml" ]; then
    echo -e "${RED}❌ VPN Gateway template not found: vpn-gateway.yaml${NC}"
    exit 1
fi

if [ ! -f "vpn-connectivity-validation.yaml" ]; then
    echo -e "${RED}❌ VPN validation template not found: vpn-connectivity-validation.yaml${NC}"
    exit 1
fi

# Check required stacks
GOVCLOUD_VPC_STACK="${PROJECT_NAME}-govcloud-vpc"
GOVCLOUD_ENDPOINTS_STACK="${PROJECT_NAME}-govcloud-endpoints"
COMMERCIAL_VPC_STACK="${PROJECT_NAME}-commercial-vpc"
COMMERCIAL_ENDPOINTS_STACK="${PROJECT_NAME}-commercial-endpoints"

check_required_stacks "$GOVCLOUD_PROFILE" "$GOVCLOUD_VPC_STACK" "$GOVCLOUD_ENDPOINTS_STACK" "GovCloud"
check_required_stacks "$COMMERCIAL_PROFILE" "$COMMERCIAL_VPC_STACK" "$COMMERCIAL_ENDPOINTS_STACK" "Commercial"

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Generate secure pre-shared keys
echo -e "${BLUE}🔐 Generating secure pre-shared keys for VPN tunnels${NC}"
TUNNEL1_PSK=$(generate_psk)
TUNNEL2_PSK=$(generate_psk)
echo "Tunnel 1 PSK: ${TUNNEL1_PSK:0:8}... (truncated for security)"
echo "Tunnel 2 PSK: ${TUNNEL2_PSK:0:8}... (truncated for security)"
echo ""

# Get public IPs for Customer Gateways
GOVCLOUD_IP=$(get_public_ip "$GOVCLOUD_PROFILE" "GovCloud")
COMMERCIAL_IP=$(get_public_ip "$COMMERCIAL_PROFILE" "Commercial")

echo -e "${BLUE}🌐 Customer Gateway IPs:${NC}"
echo "GovCloud: $GOVCLOUD_IP"
echo "Commercial: $COMMERCIAL_IP"
echo ""

echo -e "${YELLOW}⚠️  Note: These are example IPs. In production, use actual public IPs of your VPN endpoints.${NC}"
echo ""

# Deploy VPN Gateway stacks
GOVCLOUD_VPN_STACK="${PROJECT_NAME}-govcloud-vpn-gateway"
COMMERCIAL_VPN_STACK="${PROJECT_NAME}-commercial-vpn-gateway"

deploy_vpn_gateway "$GOVCLOUD_PROFILE" "$GOVCLOUD_VPN_STACK" "GovCloud" "$GOVCLOUD_VPC_STACK" "$GOVCLOUD_IP" "$COMMERCIAL_IP" "$TUNNEL1_PSK" "$TUNNEL2_PSK"
echo ""

deploy_vpn_gateway "$COMMERCIAL_PROFILE" "$COMMERCIAL_VPN_STACK" "Commercial" "$COMMERCIAL_VPC_STACK" "$GOVCLOUD_IP" "$COMMERCIAL_IP" "$TUNNEL1_PSK" "$TUNNEL2_PSK"
echo ""

# Deploy VPN validation stacks
GOVCLOUD_VALIDATION_STACK="${PROJECT_NAME}-govcloud-vpn-validation"
COMMERCIAL_VALIDATION_STACK="${PROJECT_NAME}-commercial-vpn-validation"

deploy_vpn_validation "$GOVCLOUD_PROFILE" "$GOVCLOUD_VALIDATION_STACK" "GovCloud" "$GOVCLOUD_VPC_STACK" "$GOVCLOUD_VPN_STACK"
echo ""

deploy_vpn_validation "$COMMERCIAL_PROFILE" "$COMMERCIAL_VALIDATION_STACK" "Commercial" "$COMMERCIAL_VPC_STACK" "$COMMERCIAL_VPN_STACK"
echo ""

# Display stack outputs
echo -e "${GREEN}🎉 VPN Gateway infrastructure deployment completed successfully!${NC}"
echo ""
echo -e "${YELLOW}📊 Stack Outputs:${NC}"
echo ""
echo "=== GovCloud VPN Gateway Stack Outputs ==="
get_stack_outputs "$GOVCLOUD_PROFILE" "$GOVCLOUD_VPN_STACK" "GovCloud"
echo ""
echo "=== Commercial VPN Gateway Stack Outputs ==="
get_stack_outputs "$COMMERCIAL_PROFILE" "$COMMERCIAL_VPN_STACK" "Commercial"
echo ""

# Test VPN validation functions
echo -e "${YELLOW}🧪 Testing VPN validation functions${NC}"
GOVCLOUD_VALIDATION_FUNCTION="${PROJECT_NAME}-vpn-validation"
COMMERCIAL_VALIDATION_FUNCTION="${PROJECT_NAME}-vpn-validation"

test_vpn_validation "$GOVCLOUD_PROFILE" "$GOVCLOUD_VALIDATION_FUNCTION" "GovCloud"
test_vpn_validation "$COMMERCIAL_PROFILE" "$COMMERCIAL_VALIDATION_FUNCTION" "Commercial"
echo ""

echo -e "${GREEN}✅ Next steps:${NC}"
echo "1. Wait for VPN tunnels to establish (may take 5-10 minutes)"
echo "2. Update Lambda function for VPC deployment"
echo "3. Test cross-partition connectivity"
echo "4. Monitor VPN health via CloudWatch dashboards"
echo ""
echo -e "${YELLOW}💡 Important Notes:${NC}"
echo "- VPN tunnels use BGP for dynamic routing"
echo "- Monitoring functions run every 5-15 minutes"
echo "- Check CloudWatch metrics for VPN health status"
echo "- Both tunnels should be UP for full redundancy"
echo ""
echo -e "${BLUE}🔐 Security Information:${NC}"
echo "- Pre-shared keys are stored securely in CloudFormation parameters"
echo "- VPN uses IPSec with AES-256 encryption"
echo "- All traffic is encrypted end-to-end"