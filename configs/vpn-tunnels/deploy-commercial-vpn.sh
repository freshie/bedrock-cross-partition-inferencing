#!/bin/bash

# Deploy VPN infrastructure in Commercial AWS
# This script should be run in Commercial AWS environment

set -e

PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
COMMERCIAL_VPC_ID="vpc-0c33ab87b182d9813"  # Commercial AWS default VPC
GOVCLOUD_VPC_CIDR="10.0.0.0/16"  # Adjust to match your GovCloud VPC CIDR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if VPC ID is provided
if [[ -z "$COMMERCIAL_VPC_ID" ]]; then
    log_error "Please set COMMERCIAL_VPC_ID in this script"
    exit 1
fi

log_info "Deploying VPN infrastructure in Commercial AWS..."
log_info "Project: $PROJECT_NAME"
log_info "Environment: $ENVIRONMENT"
log_info "Commercial VPC ID: $COMMERCIAL_VPC_ID"

# Deploy CloudFormation stack
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

aws cloudformation create-stack \
    --stack-name "$PROJECT_NAME-$ENVIRONMENT-commercial-vpn" \
    --template-body file://"$SCRIPT_DIR/commercial-customer-gateway.yaml" \
    --parameters \
        ParameterKey=ProjectName,ParameterValue="$PROJECT_NAME" \
        ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
        ParameterKey=GovCloudVPCCIDR,ParameterValue="$GOVCLOUD_VPC_CIDR" \
        ParameterKey=CommercialVPCId,ParameterValue="$COMMERCIAL_VPC_ID" \
    --capabilities CAPABILITY_IAM \
    --tags \
        Key=Project,Value="$PROJECT_NAME" \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=ManagedBy,Value=CloudFormation

log_success "Commercial VPN infrastructure deployment initiated"
log_info "Monitor the deployment in AWS Console or use:"
log_info "aws cloudformation describe-stacks --stack-name $PROJECT_NAME-$ENVIRONMENT-commercial-vpn"
