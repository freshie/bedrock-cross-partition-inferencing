#!/bin/bash

# Deploy comprehensive monitoring and logging infrastructure for dual routing
# This script sets up CloudWatch dashboards, alarms, and metrics processing

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
STACK_NAME=""
INTERNET_LAMBDA_NAME=""
VPN_LAMBDA_NAME=""
API_GATEWAY_ID=""
API_GATEWAY_STAGE="prod"
REQUEST_LOG_TABLE="cross-partition-requests"
ALERT_EMAIL="admin@example.com"
SLACK_WEBHOOK_URL=""

# Threshold settings
ERROR_RATE_THRESHOLD=5
LATENCY_THRESHOLD=30000
VPN_TUNNEL_DOWN_THRESHOLD=3

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
Deploy comprehensive monitoring and logging infrastructure for dual routing

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --internet-lambda NAME      Internet Lambda function name (required)
    --vpn-lambda NAME           VPN Lambda function name (required)
    --api-gateway-id ID         API Gateway ID (required)
    --api-gateway-stage STAGE   API Gateway stage name (default: prod)
    --log-table NAME           DynamoDB request log table name (default: cross-partition-requests)
    --alert-email EMAIL        Email address for alerts (default: admin@example.com)
    --slack-webhook URL        Slack webhook URL for notifications (optional)
    
    # Threshold Configuration
    --error-rate-threshold N    Error rate threshold percentage (default: 5)
    --latency-threshold N       Latency threshold in milliseconds (default: 30000)
    --vpn-tunnel-threshold N    VPN tunnel down threshold (default: 3)
    
    --help                     Show this help message

Examples:
    # Basic deployment
    $0 --internet-lambda internet-lambda-function \\
       --vpn-lambda vpn-lambda-function \\
       --api-gateway-id abcd123456 \\
       --alert-email ops@company.com
    
    # With custom thresholds and Slack
    $0 --internet-lambda internet-lambda-function \\
       --vpn-lambda vpn-lambda-function \\
       --api-gateway-id abcd123456 \\
       --alert-email ops@company.com \\
       --slack-webhook https://hooks.slack.com/... \\
       --error-rate-threshold 3 \\
       --latency-threshold 20000

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
        --internet-lambda)
            INTERNET_LAMBDA_NAME="$2"
            shift 2
            ;;
        --vpn-lambda)
            VPN_LAMBDA_NAME="$2"
            shift 2
            ;;
        --api-gateway-id)
            API_GATEWAY_ID="$2"
            shift 2
            ;;
        --api-gateway-stage)
            API_GATEWAY_STAGE="$2"
            shift 2
            ;;
        --log-table)
            REQUEST_LOG_TABLE="$2"
            shift 2
            ;;
        --alert-email)
            ALERT_EMAIL="$2"
            shift 2
            ;;
        --slack-webhook)
            SLACK_WEBHOOK_URL="$2"
            shift 2
            ;;
        --error-rate-threshold)
            ERROR_RATE_THRESHOLD="$2"
            shift 2
            ;;
        --latency-threshold)
            LATENCY_THRESHOLD="$2"
            shift 2
            ;;
        --vpn-tunnel-threshold)
            VPN_TUNNEL_DOWN_THRESHOLD="$2"
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
if [[ -z "$INTERNET_LAMBDA_NAME" ]]; then
    log_error "Internet Lambda function name is required. Use --internet-lambda parameter."
    exit 1
fi

if [[ -z "$VPN_LAMBDA_NAME" ]]; then
    log_error "VPN Lambda function name is required. Use --vpn-lambda parameter."
    exit 1
fi

if [[ -z "$API_GATEWAY_ID" ]]; then
    log_error "API Gateway ID is required. Use --api-gateway-id parameter."
    exit 1
fi

# Set stack name
STACK_NAME="${PROJECT_NAME}-monitoring-${ENVIRONMENT}"

log_info "Starting monitoring infrastructure deployment with the following configuration:"
log_info "  Project Name: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Stack Name: $STACK_NAME"
log_info "  Internet Lambda: $INTERNET_LAMBDA_NAME"
log_info "  VPN Lambda: $VPN_LAMBDA_NAME"
log_info "  API Gateway ID: $API_GATEWAY_ID"
log_info "  Alert Email: $ALERT_EMAIL"
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

# Validate resources exist
log_info "Validating resources..."

# Check Lambda functions
if ! aws lambda get-function --function-name "$INTERNET_LAMBDA_NAME" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "Internet Lambda function not found: $INTERNET_LAMBDA_NAME"
    exit 1
fi

if ! aws lambda get-function --function-name "$VPN_LAMBDA_NAME" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "VPN Lambda function not found: $VPN_LAMBDA_NAME"
    exit 1
fi

# Check API Gateway
if ! aws apigateway get-rest-api --rest-api-id "$API_GATEWAY_ID" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_error "API Gateway not found: $API_GATEWAY_ID"
    exit 1
fi

# Check DynamoDB table
if ! aws dynamodb describe-table --table-name "$REQUEST_LOG_TABLE" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_warning "DynamoDB table not found: $REQUEST_LOG_TABLE (will be created if needed)"
fi

# Create Lambda deployment package for metrics processor
log_info "Creating metrics processor deployment package..."
LAMBDA_ZIP_FILE="$PROJECT_ROOT/metrics-processor-deployment-package.zip"

# Remove existing zip file
rm -f "$LAMBDA_ZIP_FILE"

# Create temporary directory for Lambda package
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy Lambda function code
cp "$PROJECT_ROOT/lambda/dual_routing_metrics_processor.py" "$TEMP_DIR/metrics_processor.py"

# Create zip file
cd "$TEMP_DIR"
zip -r "$LAMBDA_ZIP_FILE" .
cd "$PROJECT_ROOT"

log_success "Metrics processor deployment package created: $LAMBDA_ZIP_FILE"

# Prepare CloudFormation parameters
PARAMETERS=(
    "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
    "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    "ParameterKey=InternetLambdaFunctionName,ParameterValue=$INTERNET_LAMBDA_NAME"
    "ParameterKey=VPNLambdaFunctionName,ParameterValue=$VPN_LAMBDA_NAME"
    "ParameterKey=ApiGatewayId,ParameterValue=$API_GATEWAY_ID"
    "ParameterKey=ApiGatewayStageName,ParameterValue=$API_GATEWAY_STAGE"
    "ParameterKey=RequestLogTableName,ParameterValue=$REQUEST_LOG_TABLE"
    "ParameterKey=AlertEmail,ParameterValue=$ALERT_EMAIL"
    "ParameterKey=ErrorRateThreshold,ParameterValue=$ERROR_RATE_THRESHOLD"
    "ParameterKey=LatencyThreshold,ParameterValue=$LATENCY_THRESHOLD"
    "ParameterKey=VPNTunnelDownThreshold,ParameterValue=$VPN_TUNNEL_DOWN_THRESHOLD"
)

# Add Slack webhook if provided
if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    PARAMETERS+=("ParameterKey=SlackWebhookUrl,ParameterValue=$SLACK_WEBHOOK_URL")
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
    --template-body file://"$PROJECT_ROOT/infrastructure/dual-routing-monitoring.yaml" \
    --parameters "${PARAMETERS[@]}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --tags \
        Key=Project,Value="$PROJECT_NAME" \
        Key=Environment,Value="$ENVIRONMENT" \
        Key=Component,Value="dual-routing-monitoring" \
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

# Update metrics processor Lambda function code
log_info "Updating metrics processor Lambda function code..."
METRICS_FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`MetricsProcessorFunctionArn`].OutputValue' \
    --output text | cut -d':' -f7)

if [[ -n "$METRICS_FUNCTION_NAME" ]]; then
    aws lambda update-function-code \
        --function-name "$METRICS_FUNCTION_NAME" \
        --zip-file fileb://"$LAMBDA_ZIP_FILE" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION"
    
    log_success "Metrics processor function code updated successfully"
else
    log_warning "Could not find metrics processor function name"
fi

# Get stack outputs
log_info "Retrieving stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs')

echo "$OUTPUTS" | jq -r '.[] | "\(.OutputKey): \(.OutputValue)"'

# Extract key values
DASHBOARD_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="DashboardUrl") | .OutputValue')
ALERTS_TOPIC_ARN=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="AlertsTopicArn") | .OutputValue')

# Test metrics processor function
log_info "Testing metrics processor function..."
if [[ -n "$METRICS_FUNCTION_NAME" ]]; then
    TEST_RESPONSE=$(aws lambda invoke \
        --function-name "$METRICS_FUNCTION_NAME" \
        --payload '{}' \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" \
        response.json)
    
    if echo "$TEST_RESPONSE" | jq -r '.StatusCode' | grep -q "200"; then
        log_success "Metrics processor function test successful"
        log_info "Response: $(cat response.json | jq -r '.body' | jq -r '.message')"
    else
        log_warning "Metrics processor function test returned non-200 status"
        log_info "Response: $(cat response.json)"
    fi
    
    rm -f response.json
fi

# Clean up
rm -f "$LAMBDA_ZIP_FILE"

log_success "Monitoring infrastructure deployment completed successfully!"
log_info ""
log_info "=== MONITORING RESOURCES CREATED ==="
log_info "CloudWatch Dashboard: $DASHBOARD_URL"
log_info "SNS Alerts Topic: $ALERTS_TOPIC_ARN"
log_info ""
log_info "=== CONFIGURED ALARMS ==="
log_info "✓ High error rate alarms (threshold: ${ERROR_RATE_THRESHOLD}%)"
log_info "✓ High latency alarms (threshold: ${LATENCY_THRESHOLD}ms)"
log_info "✓ VPN tunnel down alarm (threshold: ${VPN_TUNNEL_DOWN_THRESHOLD} errors)"
log_info "✓ Authentication failure alarm"
log_info ""
log_info "=== METRICS PROCESSING ==="
log_info "✓ Automated metrics processing every 5 minutes"
log_info "✓ Custom analytics and insights"
log_info "✓ Anomaly detection and alerting"
log_info ""
log_info "Next steps:"
log_info "1. Access the CloudWatch dashboard to view metrics"
log_info "2. Confirm email subscription for alerts"
log_info "3. Test alert notifications"
log_info "4. Customize thresholds as needed"
log_info "5. Set up additional monitoring integrations"