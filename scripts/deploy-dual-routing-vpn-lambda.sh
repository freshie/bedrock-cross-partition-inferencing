#!/bin/bash

# Deploy VPN Lambda function for dual routing architecture
# This script deploys the VPN Lambda function with VPC configuration

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
STACK_NAME=""
VPC_ID=""
PRIVATE_SUBNET_IDS=""
COMMERCIAL_CREDENTIALS_SECRET="cross-partition-commercial-creds"
REQUEST_LOG_TABLE="cross-partition-requests"

# VPC Endpoint URLs (optional)
SECRETS_VPC_ENDPOINT=""
DYNAMODB_VPC_ENDPOINT=""
LOGS_VPC_ENDPOINT=""
METRICS_VPC_ENDPOINT=""
COMMERCIAL_BEDROCK_ENDPOINT=""

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Deploy VPN Lambda function for dual routing architecture

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --vpc-id VPC_ID            VPC ID where Lambda will be deployed (required)
    --subnet-ids SUBNET_IDS    Comma-separated private subnet IDs (required)
    --secrets-secret NAME       Secrets Manager secret name (default: cross-partition-commercial-creds)
    --log-table NAME           DynamoDB table name (default: cross-partition-requests)
    
    # VPC Endpoint URLs (optional)
    --secrets-endpoint URL      Secrets Manager VPC endpoint URL
    --dynamodb-endpoint URL     DynamoDB VPC endpoint URL
    --logs-endpoint URL         CloudWatch Logs VPC endpoint URL
    --metrics-endpoint URL      CloudWatch Metrics VPC endpoint URL
    --bedrock-endpoint URL      Commercial Bedrock endpoint URL via VPN
    
    --help                     Show this help message

Examples:
    # Basic deployment
    $0 --vpc-id vpc-12345678 --subnet-ids subnet-12345678,subnet-87654321
    
    # With VPC endpoints
    $0 --vpc-id vpc-12345678 --subnet-ids subnet-12345678,subnet-87654321 \\
       --secrets-endpoint https://vpce-12345-secretsmanager.us-gov-west-1.vpce.amazonaws.com \\
       --dynamodb-endpoint https://vpce-12345-dynamodb.us-gov-west-1.vpce.amazonaws.com

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --govcloud-profile)
            GOVCLOUD_PROFILE="$2"
            shift 2
            ;;
        --vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        --subnet-ids)
            PRIVATE_SUBNET_IDS="$2"
            shift 2
            ;;
        --secrets-secret)
            COMMERCIAL_CREDENTIALS_SECRET="$2"
            shift 2
            ;;
        --log-table)
            REQUEST_LOG_TABLE="$2"
            shift 2
            ;;
        --secrets-endpoint)
            SECRETS_VPC_ENDPOINT="$2"
            shift 2
            ;;
        --dynamodb-endpoint)
            DYNAMODB_VPC_ENDPOINT="$2"
            shift 2
            ;;
        --logs-endpoint)
            LOGS_VPC_ENDPOINT="$2"
            shift 2
            ;;
        --metrics-endpoint)
            METRICS_VPC_ENDPOINT="$2"
            shift 2
            ;;
        --bedrock-endpoint)
            COMMERCIAL_BEDROCK_ENDPOINT="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$VPC_ID" ]]; then
    log_error "VPC ID is required. Use --vpc-id parameter."
    exit 1
fi

if [[ -z "$PRIVATE_SUBNET_IDS" ]]; then
    log_error "Private subnet IDs are required. Use --subnet-ids parameter."
    exit 1
fi

# Set stack name
STACK_NAME="${PROJECT_NAME}-vpn-lambda-${ENVIRONMENT}"

log_info "Starting VPN Lambda deployment with the following configuration:"
log_info "  Project Name: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Stack Name: $STACK_NAME"
log_info "  VPC ID: $VPC_ID"
log_info "  Private Subnet IDs: $PRIVATE_SUBNET_IDS"
log_info "  GovCloud Profile: $GOVCLOUD_PROFILE"

# Validate AWS CLI profile
if ! aws sts get-caller-identity --profile "$GOVCLOUD_PROFILE" >/dev/null 2>&1; then
    log_error "Cannot access AWS with profile '$GOVCLOUD_PROFILE'. Please check your AWS configuration."
    exit 1
fi

# Get AWS region
AWS_REGION=$(aws configure get region --profile "$GOVCLOUD_PROFILE")
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="us-gov-west-1"
    log_warning "No region configured for profile '$GOVCLOUD_PROFILE', using default: $AWS_REGION"
fi

log_info "Using AWS region: $AWS_REGION"

# Validate VPC exists
log_info "Validating VPC exists..."
if ! aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "VPC $VPC_ID not found or not accessible"
    exit 1
fi

# Validate subnets exist and are private
log_info "Validating private subnets..."
IFS=',' read -ra SUBNET_ARRAY <<< "$PRIVATE_SUBNET_IDS"
for subnet_id in "${SUBNET_ARRAY[@]}"; do
    if ! aws ec2 describe-subnets --subnet-ids "$subnet_id" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
        log_error "Subnet $subnet_id not found or not accessible"
        exit 1
    fi
done

# Create Lambda deployment package
log_info "Creating Lambda deployment package..."
LAMBDA_ZIP_FILE="$PROJECT_ROOT/lambda-vpn-deployment-package.zip"

# Remove existing zip file
rm -f "$LAMBDA_ZIP_FILE"

# Create temporary directory for Lambda package
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy Lambda function code
cp "$PROJECT_ROOT/lambda/dual_routing_vpn_lambda.py" "$TEMP_DIR/"

# Create zip file
cd "$TEMP_DIR"
zip -r "$LAMBDA_ZIP_FILE" .
cd "$PROJECT_ROOT"

log_success "Lambda deployment package created: $LAMBDA_ZIP_FILE"

# Prepare CloudFormation parameters
PARAMETERS=(
    "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
    "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    "ParameterKey=VPCId,ParameterValue=$VPC_ID"
    "ParameterKey=PrivateSubnetIds,ParameterValue=\"$PRIVATE_SUBNET_IDS\""
    "ParameterKey=CommercialCredentialsSecret,ParameterValue=$COMMERCIAL_CREDENTIALS_SECRET"
    "ParameterKey=RequestLogTable,ParameterValue=$REQUEST_LOG_TABLE"
)

# Add VPC endpoint parameters if provided
if [[ -n "$SECRETS_VPC_ENDPOINT" ]]; then
    PARAMETERS+=("ParameterKey=SecretsManagerVPCEndpoint,ParameterValue=$SECRETS_VPC_ENDPOINT")
fi

if [[ -n "$DYNAMODB_VPC_ENDPOINT" ]]; then
    PARAMETERS+=("ParameterKey=DynamoDBVPCEndpoint,ParameterValue=$DYNAMODB_VPC_ENDPOINT")
fi

if [[ -n "$LOGS_VPC_ENDPOINT" ]]; then
    PARAMETERS+=("ParameterKey=CloudWatchLogsVPCEndpoint,ParameterValue=$LOGS_VPC_ENDPOINT")
fi

if [[ -n "$METRICS_VPC_ENDPOINT" ]]; then
    PARAMETERS+=("ParameterKey=CloudWatchMetricsVPCEndpoint,ParameterValue=$METRICS_VPC_ENDPOINT")
fi

if [[ -n "$COMMERCIAL_BEDROCK_ENDPOINT" ]]; then
    PARAMETERS+=("ParameterKey=CommercialBedrockEndpoint,ParameterValue=$COMMERCIAL_BEDROCK_ENDPOINT")
fi

# Deploy CloudFormation stack
log_info "Deploying CloudFormation stack: $STACK_NAME"

# Check if stack exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_info "Stack exists, updating..."
    OPERATION="update-stack"
else
    log_info "Stack does not exist, creating..."
    OPERATION="create-stack"
fi

# Deploy stack
aws cloudformation "$OPERATION" \
    --stack-name "$STACK_NAME" \
    --template-body file://"$PROJECT_ROOT/infrastructure/dual-routing-vpn-lambda.yaml" \
    --parameters "${PARAMETERS[@]}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --tags \
        Key=Project,Value="$PROJECT_NAME" \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=Component,Value="vpn-lambda" \
        Key=ManagedBy,Value="CloudFormation"

log_info "Waiting for stack operation to complete..."

# Wait for stack operation to complete
aws cloudformation wait stack-"${OPERATION//-*/}"-complete \
    --stack-name "$STACK_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION"

# Check if operation was successful
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" --query 'Stacks[0].StackStatus' --output text | grep -q "COMPLETE"; then
    log_success "CloudFormation stack operation completed successfully"
else
    log_error "CloudFormation stack operation failed"
    exit 1
fi

# Update Lambda function code
log_info "Updating Lambda function code..."
LAMBDA_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`VPNLambdaFunctionName`].OutputValue' \
    --output text)

aws lambda update-function-code \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --zip-file fileb://"$LAMBDA_ZIP_FILE" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION"

log_success "Lambda function code updated successfully"

# Get stack outputs
log_info "Retrieving stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs')

echo "$OUTPUTS" | jq -r '.[] | "\(.OutputKey): \(.OutputValue)"'

# Test Lambda function
log_info "Testing VPN Lambda function..."
TEST_PAYLOAD='{"httpMethod":"GET","path":"/v1/vpn/bedrock/invoke-model","requestContext":{"identity":{"sourceIp":"127.0.0.1"}}}'

LAMBDA_RESPONSE=$(aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --payload "$TEST_PAYLOAD" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    response.json)

if echo "$LAMBDA_RESPONSE" | jq -r '.StatusCode' | grep -q "200"; then
    log_success "VPN Lambda function test successful"
    log_info "Response: $(cat response.json | jq -r '.body' | jq -r '.message')"
else
    log_warning "VPN Lambda function test returned non-200 status"
    log_info "Response: $(cat response.json)"
fi

# Clean up
rm -f response.json
rm -f "$LAMBDA_ZIP_FILE"

log_success "VPN Lambda deployment completed successfully!"
log_info ""
log_info "Next steps:"
log_info "1. Configure API Gateway to route /v1/vpn/bedrock/invoke-model to this Lambda function"
log_info "2. Set up VPN infrastructure if not already done"
log_info "3. Configure VPC endpoints for optimal performance"
log_info "4. Test end-to-end VPN routing"
log_info ""
log_info "Lambda Function ARN: $(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="VPNLambdaFunctionArn") | .OutputValue')"