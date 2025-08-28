#!/bin/bash

# Complete monitoring setup for dual routing system
# This script sets up dashboard, alarms, and monitoring infrastructure

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
INTERNET_LAMBDA_STACK=""
VPN_LAMBDA_STACK=""
API_GATEWAY_STACK=""
CREATE_SNS_TOPIC="false"
SNS_TOPIC_ARN=""

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
Complete monitoring setup for dual routing system

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --internet-lambda-stack NAME Internet Lambda CloudFormation stack name (required)
    --vpn-lambda-stack NAME     VPN Lambda CloudFormation stack name (required)
    --api-gateway-stack NAME    API Gateway CloudFormation stack name (required)
    --create-sns-topic          Create SNS topic for notifications
    --sns-topic-arn ARN         Existing SNS topic ARN for notifications
    --help                     Show this help message

Examples:
    # Setup complete monitoring with new SNS topic
    $0 --internet-lambda-stack my-internet-lambda-stack \\
       --vpn-lambda-stack my-vpn-lambda-stack \\
       --api-gateway-stack my-api-gateway-stack \\
       --create-sns-topic

    # Setup monitoring with existing SNS topic
    $0 --internet-lambda-stack my-internet-lambda-stack \\
       --vpn-lambda-stack my-vpn-lambda-stack \\
       --api-gateway-stack my-api-gateway-stack \\
       --sns-topic-arn arn:aws-us-gov:sns:us-gov-west-1:123456789012:alerts

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
        --internet-lambda-stack)
            INTERNET_LAMBDA_STACK="$2"
            shift 2
            ;;
        --vpn-lambda-stack)
            VPN_LAMBDA_STACK="$2"
            shift 2
            ;;
        --api-gateway-stack)
            API_GATEWAY_STACK="$2"
            shift 2
            ;;
        --create-sns-topic)
            CREATE_SNS_TOPIC="true"
            shift
            ;;
        --sns-topic-arn)
            SNS_TOPIC_ARN="$2"
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
if [[ -z "$INTERNET_LAMBDA_STACK" ]]; then
    log_error "Internet Lambda stack name is required. Use --internet-lambda-stack parameter."
    exit 1
fi

if [[ -z "$VPN_LAMBDA_STACK" ]]; then
    log_error "VPN Lambda stack name is required. Use --vpn-lambda-stack parameter."
    exit 1
fi

if [[ -z "$API_GATEWAY_STACK" ]]; then
    log_error "API Gateway stack name is required. Use --api-gateway-stack parameter."
    exit 1
fi

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

log_info "Setting up complete monitoring for dual routing system..."
log_info "  Project: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Region: $AWS_REGION"
log_info "  Internet Lambda Stack: $INTERNET_LAMBDA_STACK"
log_info "  VPN Lambda Stack: $VPN_LAMBDA_STACK"
log_info "  API Gateway Stack: $API_GATEWAY_STACK"

# Function to get CloudFormation output
get_stack_output() {
    local stack_name="$1"
    local output_key="$2"
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Get resource names from CloudFormation stacks
log_info "Retrieving resource information from CloudFormation stacks..."

INTERNET_LAMBDA_NAME=$(get_stack_output "$INTERNET_LAMBDA_STACK" "LambdaFunctionName")
if [[ -z "$INTERNET_LAMBDA_NAME" ]]; then
    INTERNET_LAMBDA_NAME=$(get_stack_output "$INTERNET_LAMBDA_STACK" "InternetLambdaFunctionName")
fi

VPN_LAMBDA_NAME=$(get_stack_output "$VPN_LAMBDA_STACK" "LambdaFunctionName")
if [[ -z "$VPN_LAMBDA_NAME" ]]; then
    VPN_LAMBDA_NAME=$(get_stack_output "$VPN_LAMBDA_STACK" "VpnLambdaFunctionName")
fi

API_GATEWAY_ID=$(get_stack_output "$API_GATEWAY_STACK" "ApiGatewayId")
if [[ -z "$API_GATEWAY_ID" ]]; then
    API_GATEWAY_ID=$(get_stack_output "$API_GATEWAY_STACK" "RestApiId")
fi

API_GATEWAY_STAGE=$(get_stack_output "$API_GATEWAY_STACK" "ApiGatewayStage")
if [[ -z "$API_GATEWAY_STAGE" ]]; then
    API_GATEWAY_STAGE="prod"
fi

# Validate we got the required information
if [[ -z "$INTERNET_LAMBDA_NAME" ]]; then
    log_error "Could not retrieve Internet Lambda function name from stack: $INTERNET_LAMBDA_STACK"
    log_error "Expected output key: LambdaFunctionName or InternetLambdaFunctionName"
    exit 1
fi

if [[ -z "$VPN_LAMBDA_NAME" ]]; then
    log_error "Could not retrieve VPN Lambda function name from stack: $VPN_LAMBDA_STACK"
    log_error "Expected output key: LambdaFunctionName or VpnLambdaFunctionName"
    exit 1
fi

if [[ -z "$API_GATEWAY_ID" ]]; then
    log_error "Could not retrieve API Gateway ID from stack: $API_GATEWAY_STACK"
    log_error "Expected output key: ApiGatewayId or RestApiId"
    exit 1
fi

log_success "Retrieved resource information:"
log_info "  Internet Lambda: $INTERNET_LAMBDA_NAME"
log_info "  VPN Lambda: $VPN_LAMBDA_NAME"
log_info "  API Gateway: $API_GATEWAY_ID"
log_info "  API Gateway Stage: $API_GATEWAY_STAGE"

# Step 1: Create CloudWatch Dashboard
log_info ""
log_info "Step 1: Creating CloudWatch Dashboard..."

"$SCRIPT_DIR/create-monitoring-dashboard.sh" \
    --project-name "$PROJECT_NAME" \
    --environment "$ENVIRONMENT" \
    --govcloud-profile "$GOVCLOUD_PROFILE" \
    --internet-lambda "$INTERNET_LAMBDA_NAME" \
    --vpn-lambda "$VPN_LAMBDA_NAME" \
    --api-gateway-id "$API_GATEWAY_ID" \
    --api-gateway-stage "$API_GATEWAY_STAGE"

# Step 2: Create CloudWatch Alarms
log_info ""
log_info "Step 2: Creating CloudWatch Alarms..."

ALARM_ARGS=(
    --project-name "$PROJECT_NAME"
    --environment "$ENVIRONMENT"
    --govcloud-profile "$GOVCLOUD_PROFILE"
    --internet-lambda "$INTERNET_LAMBDA_NAME"
    --vpn-lambda "$VPN_LAMBDA_NAME"
    --api-gateway-id "$API_GATEWAY_ID"
    --api-gateway-stage "$API_GATEWAY_STAGE"
)

if [[ "$CREATE_SNS_TOPIC" == "true" ]]; then
    ALARM_ARGS+=(--create-sns-topic)
elif [[ -n "$SNS_TOPIC_ARN" ]]; then
    ALARM_ARGS+=(--sns-topic-arn "$SNS_TOPIC_ARN")
fi

"$SCRIPT_DIR/create-dual-routing-alarms.sh" "${ALARM_ARGS[@]}"

# Step 3: Create monitoring validation script
log_info ""
log_info "Step 3: Creating monitoring validation script..."

cat > "$SCRIPT_DIR/validate-monitoring-setup.sh" << 'EOF'
#!/bin/bash

# Validate monitoring setup for dual routing system
set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name) PROJECT_NAME="$2"; shift 2 ;;
        --environment) ENVIRONMENT="$2"; shift 2 ;;
        --govcloud-profile) GOVCLOUD_PROFILE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

AWS_REGION=$(aws configure get region --profile "$GOVCLOUD_PROFILE" 2>/dev/null || echo "us-gov-west-1")
DASHBOARD_NAME="${PROJECT_NAME}-comprehensive-${ENVIRONMENT}"

log_info "Validating monitoring setup..."

# Check dashboard exists
if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    log_success "Dashboard '$DASHBOARD_NAME' exists"
else
    log_error "Dashboard '$DASHBOARD_NAME' not found"
fi

# Check alarms exist
ALARM_COUNT=$(aws cloudwatch describe-alarms --alarm-name-prefix "${PROJECT_NAME}-${ENVIRONMENT}" --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" --query 'length(MetricAlarms)' --output text 2>/dev/null || echo "0")

if [[ "$ALARM_COUNT" -gt 0 ]]; then
    log_success "Found $ALARM_COUNT alarms with prefix '${PROJECT_NAME}-${ENVIRONMENT}'"
else
    log_error "No alarms found with prefix '${PROJECT_NAME}-${ENVIRONMENT}'"
fi

# Check composite alarms
COMPOSITE_ALARM_COUNT=$(aws cloudwatch describe-alarms --alarm-name-prefix "${PROJECT_NAME}-${ENVIRONMENT}" --alarm-types CompositeAlarm --profile "$GOVCLOUD_PROFILE" --region "$AWS_REGION" --query 'length(CompositeAlarms)' --output text 2>/dev/null || echo "0")

if [[ "$COMPOSITE_ALARM_COUNT" -gt 0 ]]; then
    log_success "Found $COMPOSITE_ALARM_COUNT composite alarms"
else
    log_warning "No composite alarms found"
fi

log_info "Monitoring validation complete"
EOF

chmod +x "$SCRIPT_DIR/validate-monitoring-setup.sh"

# Step 4: Run validation
log_info ""
log_info "Step 4: Validating monitoring setup..."

"$SCRIPT_DIR/validate-monitoring-setup.sh" \
    --project-name "$PROJECT_NAME" \
    --environment "$ENVIRONMENT" \
    --govcloud-profile "$GOVCLOUD_PROFILE"

# Step 5: Create monitoring summary
log_info ""
log_info "Step 5: Creating monitoring summary..."

DASHBOARD_URL="https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${PROJECT_NAME}-comprehensive-${ENVIRONMENT}"
ALARMS_URL="https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#alarmsV2:?~(search~'${PROJECT_NAME}-${ENVIRONMENT})"

cat > "$PROJECT_ROOT/outputs/monitoring-summary.md" << EOF
# Dual Routing Monitoring Setup Summary

## Overview
Complete monitoring setup for the dual routing system has been deployed successfully.

## Environment Details
- **Project Name**: $PROJECT_NAME
- **Environment**: $ENVIRONMENT
- **AWS Region**: $AWS_REGION
- **Setup Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Resources Monitored
- **Internet Lambda**: $INTERNET_LAMBDA_NAME
- **VPN Lambda**: $VPN_LAMBDA_NAME
- **API Gateway**: $API_GATEWAY_ID (Stage: $API_GATEWAY_STAGE)

## Monitoring Components

### CloudWatch Dashboard
- **Name**: ${PROJECT_NAME}-comprehensive-${ENVIRONMENT}
- **URL**: $DASHBOARD_URL
- **Features**:
  - Request volume comparison (Internet vs VPN)
  - Latency analysis with percentiles
  - Success rate monitoring
  - Error categorization and trends
  - VPC endpoint health status
  - Traffic distribution analysis
  - Lambda function performance metrics
  - API Gateway metrics
  - Recent error log analysis

### CloudWatch Alarms
- **Total Alarms**: Created comprehensive alarm set
- **Alarm Categories**:
  - Lambda function error rates
  - Lambda function duration
  - Lambda function throttles
  - API Gateway errors (4XX, 5XX)
  - API Gateway latency
  - VPN-specific errors
  - Success rate monitoring
  - VPC endpoint health
  - VPN tunnel status
- **Composite Alarms**:
  - System health critical
  - VPN health warning
- **Alarms URL**: $ALARMS_URL

$(if [[ -n "$SNS_TOPIC_ARN" ]]; then
echo "### Notifications
- **SNS Topic**: $SNS_TOPIC_ARN
- **Note**: Configure email/SMS subscriptions for the SNS topic to receive alerts"
fi)

## Key Metrics Tracked

### Performance Metrics
- Request volume by routing method
- Response latency (average and P95)
- Success rate percentage
- Traffic distribution

### Error Metrics
- Error count by category and routing method
- Retryable vs non-retryable errors
- VPN-specific error tracking

### Infrastructure Metrics
- Lambda function performance
- API Gateway health
- VPC endpoint connectivity
- VPN tunnel status

## Alarm Thresholds

### Critical Alarms
- Lambda errors: >10 errors in 5 minutes
- API Gateway 5XX errors: >10 errors in 5 minutes
- Success rate: <95% for 3 consecutive periods
- VPN tunnel down: Immediate alert

### Warning Alarms
- Lambda duration: >30s (Internet), >45s (VPN)
- API Gateway 4XX errors: >50 errors in 5 minutes
- VPC endpoint health: <50% healthy

## Next Steps

1. **Configure Notifications**:
   - Subscribe to SNS topic for email/SMS alerts
   - Set up escalation procedures

2. **Customize Thresholds**:
   - Adjust alarm thresholds based on your requirements
   - Add custom metrics if needed

3. **Regular Monitoring**:
   - Review dashboard daily
   - Analyze trends weekly
   - Update thresholds monthly

4. **Testing**:
   - Test alarm conditions
   - Validate notification delivery
   - Practice incident response

## Validation Commands

\`\`\`bash
# Validate monitoring setup
./scripts/validate-monitoring-setup.sh \\
  --project-name $PROJECT_NAME \\
  --environment $ENVIRONMENT \\
  --govcloud-profile $GOVCLOUD_PROFILE

# View dashboard
open "$DASHBOARD_URL"

# List alarms
aws cloudwatch describe-alarms \\
  --alarm-name-prefix "${PROJECT_NAME}-${ENVIRONMENT}" \\
  --profile $GOVCLOUD_PROFILE \\
  --region $AWS_REGION
\`\`\`

## Support

For issues or questions about the monitoring setup:
1. Check CloudWatch logs for Lambda functions
2. Review alarm history in CloudWatch console
3. Validate resource configurations
4. Contact your AWS support team if needed
EOF

log_success ""
log_success "Complete monitoring setup finished successfully!"
log_info ""
log_info "Summary:"
log_info "✓ CloudWatch Dashboard created"
log_info "✓ CloudWatch Alarms configured"
log_info "✓ Composite Alarms for system health"
log_info "✓ Monitoring validation script created"
log_info "✓ Monitoring summary documentation generated"
log_info ""
log_info "Dashboard URL: $DASHBOARD_URL"
log_info "Alarms URL: $ALARMS_URL"
log_info "Summary: $PROJECT_ROOT/outputs/monitoring-summary.md"
log_info ""
log_info "Next steps:"
log_info "1. Access the dashboard and alarms URLs above"
log_info "2. Configure SNS topic subscriptions for notifications"
log_info "3. Test alarm conditions and notification delivery"
log_info "4. Review and adjust thresholds as needed"