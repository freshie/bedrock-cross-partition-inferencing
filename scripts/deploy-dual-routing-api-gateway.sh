#!/bin/bash

# Deploy API Gateway resource structure for dual routing
# This script creates or extends API Gateway with VPN routing paths

set -e

# Default values
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
AWS_PROFILE=""
STACK_NAME=""
EXISTING_API_GATEWAY_ID=""
INTERNET_LAMBDA_ARN=""
VPN_LAMBDA_ARN=""
API_GATEWAY_NAME="dual-routing-bedrock-api"
CREATE_API_KEY="true"
API_KEY_NAME="dual-routing-bedrock-key"

# Throttling and quota settings
THROTTLE_BURST_LIMIT=100
THROTTLE_RATE_LIMIT=50
QUOTA_LIMIT=10000

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
Deploy API Gateway resource structure for dual routing

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: dual-routing-api-gateway)
    --environment ENV           Environment (dev/stage/prod, default: prod)
    --aws-profile PROFILE       AWS CLI profile (optional)
    --region REGION             AWS region (default: us-gov-west-1)
    --existing-api-id ID        Existing API Gateway ID to extend (optional)
    --internet-lambda-arn ARN   ARN of the Internet Lambda function (required)
    --vpn-lambda-arn ARN        ARN of the VPN Lambda function (required)
    --internet-lambda-stack STACK  Internet Lambda CloudFormation stack name (auto-discover ARN)
    --vpn-lambda-stack STACK    VPN Lambda CloudFormation stack name (auto-discover ARN)
    --api-gateway-name NAME     Name for new API Gateway (default: dual-routing-bedrock-api)
    --create-api-key BOOL       Create API key (true/false, default: true)
    --api-key-name NAME         API key name (default: dual-routing-bedrock-key)
    --throttle-burst LIMIT      Throttle burst limit (default: 100)
    --throttle-rate LIMIT       Throttle rate limit (default: 50)
    --quota-limit LIMIT         Daily quota limit (default: 10000)
    --validate-only             Only validate template and parameters
    --dry-run                   Show what would be deployed without executing
    --help                      Show this help message

Examples:
    # Create new API Gateway with dual routing using stack names
    $0 --internet-lambda-stack dual-routing-api-gateway-prod-internet-lambda \\
       --vpn-lambda-stack dual-routing-api-gateway-prod-vpn-lambda
    
    # Create with explicit Lambda ARNs
    $0 --internet-lambda-arn arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:internet-lambda \\
       --vpn-lambda-arn arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:vpn-lambda
    
    # Extend existing API Gateway
    $0 --existing-api-id abcd123456 \\
       --internet-lambda-stack dual-routing-api-gateway-prod-internet-lambda \\
       --vpn-lambda-stack dual-routing-api-gateway-prod-vpn-lambda

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
        --aws-profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --existing-api-id)
            EXISTING_API_GATEWAY_ID="$2"
            shift 2
            ;;
        --internet-lambda-arn)
            INTERNET_LAMBDA_ARN="$2"
            shift 2
            ;;
        --vpn-lambda-arn)
            VPN_LAMBDA_ARN="$2"
            shift 2
            ;;
        --internet-lambda-stack)
            INTERNET_LAMBDA_STACK="$2"
            shift 2
            ;;
        --vpn-lambda-stack)
            VPN_LAMBDA_STACK="$2"
            shift 2
            ;;
        --api-gateway-name)
            API_GATEWAY_NAME="$2"
            shift 2
            ;;
        --create-api-key)
            CREATE_API_KEY="$2"
            shift 2
            ;;
        --api-key-name)
            API_KEY_NAME="$2"
            shift 2
            ;;
        --throttle-burst)
            THROTTLE_BURST_LIMIT="$2"
            shift 2
            ;;
        --throttle-rate)
            THROTTLE_RATE_LIMIT="$2"
            shift 2
            ;;
        --quota-limit)
            QUOTA_LIMIT="$2"
            shift 2
            ;;
        --validate-only)
            VALIDATE_ONLY="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
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

# Function to get Lambda ARN from CloudFormation stack
get_lambda_arn_from_stack() {
    local stack_name="$1"
    local output_key="$2"
    
    if [[ -n "$AWS_PROFILE" ]]; then
        aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --profile "$AWS_PROFILE" \
            --region "${AWS_REGION:-us-gov-west-1}" \
            --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
            --output text 2>/dev/null
    else
        aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "${AWS_REGION:-us-gov-west-1}" \
            --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
            --output text 2>/dev/null
    fi
}

# Auto-discover Lambda ARNs from CloudFormation stacks if not provided
if [[ -z "$INTERNET_LAMBDA_ARN" && -n "$INTERNET_LAMBDA_STACK" ]]; then
    log_info "Auto-discovering Internet Lambda ARN from stack: $INTERNET_LAMBDA_STACK"
    INTERNET_LAMBDA_ARN=$(get_lambda_arn_from_stack "$INTERNET_LAMBDA_STACK" "InternetLambdaFunctionArn")
    if [[ -z "$INTERNET_LAMBDA_ARN" || "$INTERNET_LAMBDA_ARN" == "None" ]]; then
        # Try alternative output key names
        INTERNET_LAMBDA_ARN=$(get_lambda_arn_from_stack "$INTERNET_LAMBDA_STACK" "LambdaFunctionArn")
    fi
    if [[ -n "$INTERNET_LAMBDA_ARN" && "$INTERNET_LAMBDA_ARN" != "None" ]]; then
        log_success "Found Internet Lambda ARN: $INTERNET_LAMBDA_ARN"
    else
        log_error "Could not find Internet Lambda ARN in stack: $INTERNET_LAMBDA_STACK"
        exit 1
    fi
fi

if [[ -z "$VPN_LAMBDA_ARN" && -n "$VPN_LAMBDA_STACK" ]]; then
    log_info "Auto-discovering VPN Lambda ARN from stack: $VPN_LAMBDA_STACK"
    VPN_LAMBDA_ARN=$(get_lambda_arn_from_stack "$VPN_LAMBDA_STACK" "VPNLambdaFunctionArn")
    if [[ -z "$VPN_LAMBDA_ARN" || "$VPN_LAMBDA_ARN" == "None" ]]; then
        # Try alternative output key names
        VPN_LAMBDA_ARN=$(get_lambda_arn_from_stack "$VPN_LAMBDA_STACK" "LambdaFunctionArn")
    fi
    if [[ -n "$VPN_LAMBDA_ARN" && "$VPN_LAMBDA_ARN" != "None" ]]; then
        log_success "Found VPN Lambda ARN: $VPN_LAMBDA_ARN"
    else
        log_error "Could not find VPN Lambda ARN in stack: $VPN_LAMBDA_STACK"
        exit 1
    fi
fi

# Validate required parameters
if [[ -z "$INTERNET_LAMBDA_ARN" ]]; then
    log_error "Internet Lambda ARN is required. Use --internet-lambda-arn or --internet-lambda-stack parameter."
    exit 1
fi

if [[ -z "$VPN_LAMBDA_ARN" ]]; then
    log_error "VPN Lambda ARN is required. Use --vpn-lambda-arn or --vpn-lambda-stack parameter."
    exit 1
fi

# Set stack name
STACK_NAME="${PROJECT_NAME}-api-gateway-${ENVIRONMENT}"

# Determine operation type
if [[ -n "$EXISTING_API_GATEWAY_ID" ]]; then
    OPERATION_TYPE="extend"
    log_info "Extending existing API Gateway: $EXISTING_API_GATEWAY_ID"
else
    OPERATION_TYPE="create"
    log_info "Creating new API Gateway"
fi

# Set default AWS region
AWS_REGION="${AWS_REGION:-us-gov-west-1}"

log_info "Starting API Gateway deployment with the following configuration:"
log_info "  Project Name: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Stack Name: $STACK_NAME"
log_info "  Operation: $OPERATION_TYPE"
log_info "  Internet Lambda ARN: $INTERNET_LAMBDA_ARN"
log_info "  VPN Lambda ARN: $VPN_LAMBDA_ARN"
log_info "  AWS Profile: ${AWS_PROFILE:-default}"
log_info "  AWS Region: $AWS_REGION"

# Validate AWS CLI access
if [[ -n "$AWS_PROFILE" ]]; then
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
        log_error "Cannot access AWS with profile '$AWS_PROFILE'. Please check your AWS configuration."
        exit 1
    fi
else
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "Cannot access AWS. Please check your AWS configuration or specify --aws-profile."
        exit 1
    fi
fi

log_info "Using AWS region: $AWS_REGION"

# Function to run AWS CLI commands with optional profile
aws_cmd() {
    if [[ -n "$AWS_PROFILE" ]]; then
        aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
    else
        aws --region "$AWS_REGION" "$@"
    fi
}

# Validate Lambda functions exist
log_info "Validating Lambda functions..."
if ! aws_cmd lambda get-function --function-name "${INTERNET_LAMBDA_ARN##*:}" >/dev/null 2>&1; then
    log_error "Internet Lambda function not found: $INTERNET_LAMBDA_ARN"
    exit 1
fi

if ! aws_cmd lambda get-function --function-name "${VPN_LAMBDA_ARN##*:}" >/dev/null 2>&1; then
    log_error "VPN Lambda function not found: $VPN_LAMBDA_ARN"
    exit 1
fi

log_success "Lambda functions validated successfully"

# Validate existing API Gateway if specified
if [[ -n "$EXISTING_API_GATEWAY_ID" ]]; then
    log_info "Validating existing API Gateway..."
    if ! aws_cmd apigateway get-rest-api --rest-api-id "$EXISTING_API_GATEWAY_ID" >/dev/null 2>&1; then
        log_error "Existing API Gateway not found: $EXISTING_API_GATEWAY_ID"
        exit 1
    fi
    log_success "Existing API Gateway validated"
fi

# Validate CloudFormation template
log_info "Validating CloudFormation template..."
if ! aws_cmd cloudformation validate-template --template-body file://"$PROJECT_ROOT/infrastructure/dual-routing-api-gateway.yaml" >/dev/null 2>&1; then
    log_error "CloudFormation template validation failed"
    exit 1
fi
log_success "CloudFormation template is valid"

# Prepare CloudFormation parameters
PARAMETERS=(
    "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
    "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    "ParameterKey=InternetLambdaFunctionArn,ParameterValue=$INTERNET_LAMBDA_ARN"
    "ParameterKey=VPNLambdaFunctionArn,ParameterValue=$VPN_LAMBDA_ARN"
    "ParameterKey=ApiGatewayName,ParameterValue=$API_GATEWAY_NAME"
    "ParameterKey=CreateApiKey,ParameterValue=$CREATE_API_KEY"
    "ParameterKey=ApiKeyName,ParameterValue=$API_KEY_NAME"
    "ParameterKey=ThrottleBurstLimit,ParameterValue=$THROTTLE_BURST_LIMIT"
    "ParameterKey=ThrottleRateLimit,ParameterValue=$THROTTLE_RATE_LIMIT"
    "ParameterKey=QuotaLimit,ParameterValue=$QUOTA_LIMIT"
)

# Add existing API Gateway ID if specified
if [[ -n "$EXISTING_API_GATEWAY_ID" ]]; then
    PARAMETERS+=("ParameterKey=ExistingApiGatewayId,ParameterValue=$EXISTING_API_GATEWAY_ID")
fi

# Exit early if validate-only or dry-run
if [[ "$VALIDATE_ONLY" == "true" ]]; then
    log_success "Validation completed successfully"
    exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN: Would deploy CloudFormation stack with the following parameters:"
    for param in "${PARAMETERS[@]}"; do
        log_info "  $param"
    done
    exit 0
fi

# Deploy CloudFormation stack
log_info "Deploying CloudFormation stack: $STACK_NAME"

# Check if stack exists
if aws_cmd cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
    log_info "Stack exists, updating..."
    OPERATION="update-stack"
else
    log_info "Stack does not exist, creating..."
    OPERATION="create-stack"
fi

# Deploy stack
aws_cmd cloudformation "$OPERATION" \
    --stack-name "$STACK_NAME" \
    --template-body file://"$PROJECT_ROOT/infrastructure/dual-routing-api-gateway.yaml" \
    --parameters "${PARAMETERS[@]}" \
    --capabilities CAPABILITY_IAM \
    --tags \
        Key=Project,Value="$PROJECT_NAME" \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=Component,Value="dual-routing-api-gateway" \
        Key=ManagedBy,Value="CloudFormation"

log_info "Waiting for stack operation to complete..."

# Wait for stack operation to complete
aws_cmd cloudformation wait stack-"${OPERATION//-*/}"-complete --stack-name "$STACK_NAME"

# Check if operation was successful
STACK_STATUS=$(aws_cmd cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackStatus' --output text)
if echo "$STACK_STATUS" | grep -q "COMPLETE"; then
    log_success "CloudFormation stack operation completed successfully"
else
    log_error "CloudFormation stack operation failed with status: $STACK_STATUS"
    exit 1
fi

# Get stack outputs
log_info "Retrieving stack outputs..."
OUTPUTS=$(aws_cmd cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs')

if command -v jq >/dev/null 2>&1; then
    echo "$OUTPUTS" | jq -r '.[] | "\(.OutputKey): \(.OutputValue)"'
else
    echo "$OUTPUTS"
fi

# Extract key values for testing
if command -v jq >/dev/null 2>&1; then
    API_GATEWAY_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiGatewayUrl") | .OutputValue')
    INTERNET_ENDPOINT=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="InternetEndpoint") | .OutputValue')
    VPN_ENDPOINT=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="VPNEndpoint") | .OutputValue')
    API_KEY_VALUE=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiKeyValue") | .OutputValue')
else
    log_warning "jq not available - skipping endpoint extraction for testing"
    API_GATEWAY_URL=""
    INTERNET_ENDPOINT=""
    VPN_ENDPOINT=""
    API_KEY_VALUE=""
fi

# Test API Gateway endpoints
if [[ -n "$INTERNET_ENDPOINT" && -n "$VPN_ENDPOINT" ]]; then
    log_info "Testing API Gateway endpoints..."
    
    # Test Internet endpoint
    if command -v curl >/dev/null 2>&1; then
        log_info "Testing Internet routing endpoint..."
        INTERNET_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/internet_test.json "$INTERNET_ENDPOINT" || echo "000")
        if [[ "$INTERNET_RESPONSE" == "200" ]]; then
            log_success "Internet endpoint test successful"
            if command -v jq >/dev/null 2>&1 && [[ -f /tmp/internet_test.json ]]; then
                log_info "Response: $(cat /tmp/internet_test.json | jq -r '.message // .error.message // "No message"' 2>/dev/null || echo "Response received")"
            fi
        else
            log_warning "Internet endpoint test returned status: $INTERNET_RESPONSE"
        fi
        
        # Test VPN endpoint
        log_info "Testing VPN routing endpoint..."
        VPN_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/vpn_test.json "$VPN_ENDPOINT" || echo "000")
        if [[ "$VPN_RESPONSE" == "200" ]]; then
            log_success "VPN endpoint test successful"
            if command -v jq >/dev/null 2>&1 && [[ -f /tmp/vpn_test.json ]]; then
                log_info "Response: $(cat /tmp/vpn_test.json | jq -r '.message // .error.message // "No message"' 2>/dev/null || echo "Response received")"
            fi
        else
            log_warning "VPN endpoint test returned status: $VPN_RESPONSE"
        fi
        
        # Clean up test files
        rm -f /tmp/internet_test.json /tmp/vpn_test.json
    else
        log_warning "curl not available - skipping endpoint testing"
    fi
else
    log_warning "Endpoint URLs not available - skipping endpoint testing"
fi

# Display API key if created
if [[ "$CREATE_API_KEY" == "true" && -n "$API_KEY_VALUE" && "$API_KEY_VALUE" != "null" ]]; then
    log_info ""
    log_info "API Key created: $API_KEY_VALUE"
    log_info "Include this key in requests using the 'X-API-Key' header"
fi

log_success "API Gateway deployment completed successfully!"
log_info ""
log_info "Endpoints available:"
log_info "  Internet Routing: $INTERNET_ENDPOINT"
log_info "  VPN Routing: $VPN_ENDPOINT"
log_info "  Base URL: $API_GATEWAY_URL"
log_info ""
log_info "Resource structure:"
log_info "  /v1/bedrock/invoke-model     → Internet Lambda (existing clients)"
log_info "  /v1/vpn/bedrock/invoke-model → VPN Lambda (new secure routing)"
log_info "  /v1/bedrock/models           → Internet Lambda (model listing)"
log_info "  /v1/vpn/bedrock/models       → VPN Lambda (model listing via VPN)"
log_info ""
log_info "Next steps:"
log_info "1. Test both routing methods with your applications"
log_info "2. Update client applications to use VPN endpoints as needed"
log_info "3. Monitor performance and error rates for both routing methods"
log_info "4. Configure additional monitoring and alerting"