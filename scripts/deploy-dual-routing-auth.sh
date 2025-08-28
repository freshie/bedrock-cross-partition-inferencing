#!/bin/bash

# Deploy authentication and authorization infrastructure for dual routing
# This script sets up API keys, usage plans, IAM roles, and Lambda authorizer

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
STACK_NAME=""
API_GATEWAY_ID=""
AUTHENTICATION_METHOD="API_KEY"
CREATE_API_KEYS="true"
CREATE_IAM_ROLES="true"

# Throttling and quota settings
INTERNET_THROTTLE_BURST=100
INTERNET_THROTTLE_RATE=50
VPN_THROTTLE_BURST=200
VPN_THROTTLE_RATE=100
ADMIN_THROTTLE_BURST=500
ADMIN_THROTTLE_RATE=200

INTERNET_QUOTA=10000
VPN_QUOTA=20000
ADMIN_QUOTA=50000

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
Deploy authentication and authorization infrastructure for dual routing

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --api-gateway-id ID         API Gateway ID to configure auth for (required)
    --auth-method METHOD        Authentication method (API_KEY/IAM/LAMBDA_AUTHORIZER, default: API_KEY)
    --create-api-keys BOOL      Create API keys (true/false, default: true)
    --create-iam-roles BOOL     Create IAM roles (true/false, default: true)
    
    # Throttling Configuration
    --internet-throttle-burst N  Internet throttle burst limit (default: 100)
    --internet-throttle-rate N   Internet throttle rate limit (default: 50)
    --vpn-throttle-burst N       VPN throttle burst limit (default: 200)
    --vpn-throttle-rate N        VPN throttle rate limit (default: 100)
    --admin-throttle-burst N     Admin throttle burst limit (default: 500)
    --admin-throttle-rate N      Admin throttle rate limit (default: 200)
    
    # Quota Configuration
    --internet-quota N          Internet daily quota (default: 10000)
    --vpn-quota N               VPN daily quota (default: 20000)
    --admin-quota N             Admin daily quota (default: 50000)
    
    --help                      Show this help message

Examples:
    # Deploy with API key authentication
    $0 --api-gateway-id abcd123456
    
    # Deploy with custom throttling
    $0 --api-gateway-id abcd123456 \\
       --vpn-throttle-burst 300 \\
       --vpn-throttle-rate 150

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
        --api-gateway-id)
            API_GATEWAY_ID="$2"
            shift 2
            ;;
        --auth-method)
            AUTHENTICATION_METHOD="$2"
            shift 2
            ;;
        --create-api-keys)
            CREATE_API_KEYS="$2"
            shift 2
            ;;
        --create-iam-roles)
            CREATE_IAM_ROLES="$2"
            shift 2
            ;;
        --internet-throttle-burst)
            INTERNET_THROTTLE_BURST="$2"
            shift 2
            ;;
        --internet-throttle-rate)
            INTERNET_THROTTLE_RATE="$2"
            shift 2
            ;;
        --vpn-throttle-burst)
            VPN_THROTTLE_BURST="$2"
            shift 2
            ;;
        --vpn-throttle-rate)
            VPN_THROTTLE_RATE="$2"
            shift 2
            ;;
        --admin-throttle-burst)
            ADMIN_THROTTLE_BURST="$2"
            shift 2
            ;;
        --admin-throttle-rate)
            ADMIN_THROTTLE_RATE="$2"
            shift 2
            ;;
        --internet-quota)
            INTERNET_QUOTA="$2"
            shift 2
            ;;
        --vpn-quota)
            VPN_QUOTA="$2"
            shift 2
            ;;
        --admin-quota)
            ADMIN_QUOTA="$2"
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
if [[ -z "$API_GATEWAY_ID" ]]; then
    log_error "API Gateway ID is required. Use --api-gateway-id parameter."
    exit 1
fi

# Set stack name
STACK_NAME="${PROJECT_NAME}-auth-${ENVIRONMENT}"

log_info "Starting authentication infrastructure deployment with the following configuration:"
log_info "  Project Name: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Stack Name: $STACK_NAME"
log_info "  API Gateway ID: $API_GATEWAY_ID"
log_info "  Authentication Method: $AUTHENTICATION_METHOD"
log_info "  Create API Keys: $CREATE_API_KEYS"
log_info "  Create IAM Roles: $CREATE_IAM_ROLES"
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

# Validate API Gateway exists
log_info "Validating API Gateway..."
if ! aws apigateway get-rest-api --rest-api-id "$API_GATEWAY_ID" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "API Gateway not found: $API_GATEWAY_ID"
    exit 1
fi

# Prepare CloudFormation parameters
PARAMETERS=(
    "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
    "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    "ParameterKey=ApiGatewayId,ParameterValue=$API_GATEWAY_ID"
    "ParameterKey=AuthenticationMethod,ParameterValue=$AUTHENTICATION_METHOD"
    "ParameterKey=CreateApiKeys,ParameterValue=$CREATE_API_KEYS"
    "ParameterKey=CreateIAMRoles,ParameterValue=$CREATE_IAM_ROLES"
    "ParameterKey=InternetThrottleBurst,ParameterValue=$INTERNET_THROTTLE_BURST"
    "ParameterKey=InternetThrottleRate,ParameterValue=$INTERNET_THROTTLE_RATE"
    "ParameterKey=VPNThrottleBurst,ParameterValue=$VPN_THROTTLE_BURST"
    "ParameterKey=VPNThrottleRate,ParameterValue=$VPN_THROTTLE_RATE"
    "ParameterKey=AdminThrottleBurst,ParameterValue=$ADMIN_THROTTLE_BURST"
    "ParameterKey=AdminThrottleRate,ParameterValue=$ADMIN_THROTTLE_RATE"
    "ParameterKey=InternetQuotaLimit,ParameterValue=$INTERNET_QUOTA"
    "ParameterKey=VPNQuotaLimit,ParameterValue=$VPN_QUOTA"
    "ParameterKey=AdminQuotaLimit,ParameterValue=$ADMIN_QUOTA"
)

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
    --template-body file://"$PROJECT_ROOT/infrastructure/dual-routing-auth.yaml" \
    --parameters "${PARAMETERS[@]}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --tags \
        Key=Project,Value="$PROJECT_NAME" \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=Component,Value="dual-routing-auth" \
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

# Get stack outputs
log_info "Retrieving stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs')

echo "$OUTPUTS" | jq -r '.[] | "\(.OutputKey): \(.OutputValue)"'

# Extract API keys if created
if [[ "$CREATE_API_KEYS" == "true" ]]; then
    log_info ""
    log_info "=== API KEYS CREATED ==="
    
    INTERNET_API_KEY=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="InternetApiKeyValue") | .OutputValue')
    VPN_API_KEY=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="VPNApiKeyValue") | .OutputValue')
    ADMIN_API_KEY=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AdminApiKeyValue") | .OutputValue')
    
    if [[ -n "$INTERNET_API_KEY" && "$INTERNET_API_KEY" != "null" ]]; then
        log_info "Internet Routing API Key: $INTERNET_API_KEY"
    fi
    
    if [[ -n "$VPN_API_KEY" && "$VPN_API_KEY" != "null" ]]; then
        log_info "VPN Routing API Key: $VPN_API_KEY"
    fi
    
    if [[ -n "$ADMIN_API_KEY" && "$ADMIN_API_KEY" != "null" ]]; then
        log_info "Admin API Key: $ADMIN_API_KEY"
    fi
    
    log_info ""
    log_info "API keys are also stored securely in AWS Secrets Manager:"
    log_info "  Internet: ${PROJECT_NAME}/api-keys/internet-routing-${ENVIRONMENT}"
    log_info "  VPN: ${PROJECT_NAME}/api-keys/vpn-routing-${ENVIRONMENT}"
    log_info "  Admin: ${PROJECT_NAME}/api-keys/admin-${ENVIRONMENT}"
fi

# Extract IAM roles if created
if [[ "$CREATE_IAM_ROLES" == "true" ]]; then
    log_info ""
    log_info "=== IAM ROLES CREATED ==="
    
    INTERNET_ROLE_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="InternetRoleArn") | .OutputValue')
    VPN_ROLE_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="VPNRoleArn") | .OutputValue')
    ADMIN_ROLE_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AdminRoleArn") | .OutputValue')
    
    if [[ -n "$INTERNET_ROLE_ARN" && "$INTERNET_ROLE_ARN" != "null" ]]; then
        log_info "Internet Routing Role: $INTERNET_ROLE_ARN"
        log_info "  External ID: ${PROJECT_NAME}-internet-${ENVIRONMENT}"
    fi
    
    if [[ -n "$VPN_ROLE_ARN" && "$VPN_ROLE_ARN" != "null" ]]; then
        log_info "VPN Routing Role: $VPN_ROLE_ARN"
        log_info "  External ID: ${PROJECT_NAME}-vpn-${ENVIRONMENT}"
    fi
    
    if [[ -n "$ADMIN_ROLE_ARN" && "$ADMIN_ROLE_ARN" != "null" ]]; then
        log_info "Admin Role: $ADMIN_ROLE_ARN"
        log_info "  External ID: ${PROJECT_NAME}-admin-${ENVIRONMENT}"
    fi
fi

# Create authentication secrets for Lambda authorizer (if needed)
if [[ "$AUTHENTICATION_METHOD" == "LAMBDA_AUTHORIZER" ]]; then
    log_info ""
    log_info "Setting up Lambda authorizer secrets..."
    
    # Create auth secrets
    AUTH_SECRETS=$(cat << EOF
{
    "api_keys": {
        "internet": ["${INTERNET_API_KEY:-sample-internet-key}"],
        "vpn": ["${VPN_API_KEY:-sample-vpn-key}"],
        "admin": ["${ADMIN_API_KEY:-sample-admin-key}"]
    },
    "jwt": {
        "secret_key": "$(openssl rand -base64 32)"
    },
    "custom_tokens": {
        "secret_key": "$(openssl rand -base64 32)"
    }
}
EOF
    )
    
    # Store in Secrets Manager
    SECRET_NAME="dual-routing-auth-secrets"
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
        aws secretsmanager update-secret \
            --secret-id "$SECRET_NAME" \
            --secret-string "$AUTH_SECRETS" \
            --profile "$GOVCLOUD_PROFILE" \
            --region "$AWS_REGION" >/dev/null
        log_info "Updated Lambda authorizer secrets in Secrets Manager"
    else
        aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --description "Authentication secrets for dual routing Lambda authorizer" \
            --secret-string "$AUTH_SECRETS" \
            --profile "$GOVCLOUD_PROFILE" \
            --region "$AWS_REGION" >/dev/null
        log_info "Created Lambda authorizer secrets in Secrets Manager"
    fi
fi

log_success "Authentication infrastructure deployment completed successfully!"
log_info ""
log_info "Authentication Configuration:"
log_info "  Method: $AUTHENTICATION_METHOD"
log_info "  API Keys Created: $CREATE_API_KEYS"
log_info "  IAM Roles Created: $CREATE_IAM_ROLES"
log_info ""
log_info "Usage Plans:"
log_info "  Internet Routing: ${INTERNET_THROTTLE_RATE} req/sec, ${INTERNET_QUOTA} req/day"
log_info "  VPN Routing: ${VPN_THROTTLE_RATE} req/sec, ${VPN_QUOTA} req/day"
log_info "  Admin Access: ${ADMIN_THROTTLE_RATE} req/sec, ${ADMIN_QUOTA} req/day"
log_info ""
log_info "Next steps:"
log_info "1. Test authentication with both routing methods"
log_info "2. Distribute API keys to authorized users/applications"
log_info "3. Configure monitoring for authentication events"
log_info "4. Set up key rotation procedures"