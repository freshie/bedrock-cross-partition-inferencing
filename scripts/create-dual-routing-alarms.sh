#!/bin/bash

# Create CloudWatch alarms for dual routing monitoring
# This script creates comprehensive alarms for both internet and VPN routing

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
INTERNET_LAMBDA_NAME=""
VPN_LAMBDA_NAME=""
API_GATEWAY_ID=""
API_GATEWAY_STAGE="prod"
SNS_TOPIC_ARN=""
CREATE_SNS_TOPIC="false"

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
Create CloudWatch alarms for dual routing monitoring

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --internet-lambda NAME      Internet Lambda function name (required)
    --vpn-lambda NAME           VPN Lambda function name (required)
    --api-gateway-id ID         API Gateway ID (required)
    --api-gateway-stage STAGE   API Gateway stage name (default: prod)
    --sns-topic-arn ARN         SNS topic ARN for notifications (optional)
    --create-sns-topic          Create SNS topic for notifications
    --help                     Show this help message

Examples:
    # Create alarms with existing SNS topic
    $0 --internet-lambda internet-lambda-function \\
       --vpn-lambda vpn-lambda-function \\
       --api-gateway-id abcd123456 \\
       --sns-topic-arn arn:aws-us-gov:sns:us-gov-west-1:123456789012:alerts

    # Create alarms and SNS topic
    $0 --internet-lambda internet-lambda-function \\
       --vpn-lambda vpn-lambda-function \\
       --api-gateway-id abcd123456 \\
       --create-sns-topic

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
        --sns-topic-arn)
            SNS_TOPIC_ARN="$2"
            shift 2
            ;;
        --create-sns-topic)
            CREATE_SNS_TOPIC="true"
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

# Validate AWS CLI profile
if ! aws sts get-caller-identity --profile "$GOVCLOUD_PROFILE" >/dev/null 2>&1; then
    log_error "Cannot access AWS with profile '$GOVCLOUD_PROFILE'. Please check your AWS configuration."
    exit 1
fi

# Get AWS region and account ID
AWS_REGION=$(aws configure get region --profile "$GOVCLOUD_PROFILE")
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="us-gov-west-1"
    log_warning "No region configured for profile '$GOVCLOUD_PROFILE', using default: $AWS_REGION"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$GOVCLOUD_PROFILE" --query Account --output text)

# Create SNS topic if requested
if [[ "$CREATE_SNS_TOPIC" == "true" ]]; then
    TOPIC_NAME="${PROJECT_NAME}-${ENVIRONMENT}-alerts"
    log_info "Creating SNS topic: $TOPIC_NAME"
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$TOPIC_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" \
        --query TopicArn --output text)
    
    log_success "Created SNS topic: $SNS_TOPIC_ARN"
fi

log_info "Creating CloudWatch alarms for dual routing monitoring..."
log_info "  Internet Lambda: $INTERNET_LAMBDA_NAME"
log_info "  VPN Lambda: $VPN_LAMBDA_NAME"
log_info "  API Gateway: $API_GATEWAY_ID"
log_info "  Region: $AWS_REGION"
if [[ -n "$SNS_TOPIC_ARN" ]]; then
    log_info "  SNS Topic: $SNS_TOPIC_ARN"
fi

# Function to create alarm
create_alarm() {
    local alarm_name="$1"
    local alarm_description="$2"
    local metric_name="$3"
    local namespace="$4"
    local statistic="$5"
    local threshold="$6"
    local comparison_operator="$7"
    local evaluation_periods="$8"
    local period="$9"
    local dimensions="${10}"
    
    local alarm_actions=""
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        alarm_actions="--alarm-actions $SNS_TOPIC_ARN --ok-actions $SNS_TOPIC_ARN"
    fi
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "$alarm_description" \
        --metric-name "$metric_name" \
        --namespace "$namespace" \
        --statistic "$statistic" \
        --threshold "$threshold" \
        --comparison-operator "$comparison_operator" \
        --evaluation-periods "$evaluation_periods" \
        --period "$period" \
        --dimensions "$dimensions" \
        $alarm_actions \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION"
    
    log_success "Created alarm: $alarm_name"
}

# 1. Lambda Function Error Rate Alarms
log_info "Creating Lambda function error rate alarms..."

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-internet-lambda-high-errors" \
    "High error rate for Internet Lambda function" \
    "Errors" \
    "AWS/Lambda" \
    "Sum" \
    "10" \
    "GreaterThanThreshold" \
    "2" \
    "300" \
    "Name=FunctionName,Value=$INTERNET_LAMBDA_NAME"

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-vpn-lambda-high-errors" \
    "High error rate for VPN Lambda function" \
    "Errors" \
    "AWS/Lambda" \
    "Sum" \
    "10" \
    "GreaterThanThreshold" \
    "2" \
    "300" \
    "Name=FunctionName,Value=$VPN_LAMBDA_NAME"

# 2. Lambda Function Duration Alarms
log_info "Creating Lambda function duration alarms..."

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-internet-lambda-high-duration" \
    "High duration for Internet Lambda function" \
    "Duration" \
    "AWS/Lambda" \
    "Average" \
    "30000" \
    "GreaterThanThreshold" \
    "3" \
    "300" \
    "Name=FunctionName,Value=$INTERNET_LAMBDA_NAME"

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-vpn-lambda-high-duration" \
    "High duration for VPN Lambda function" \
    "Duration" \
    "AWS/Lambda" \
    "Average" \
    "45000" \
    "GreaterThanThreshold" \
    "3" \
    "300" \
    "Name=FunctionName,Value=$VPN_LAMBDA_NAME"

# 3. Lambda Function Throttle Alarms
log_info "Creating Lambda function throttle alarms..."

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-internet-lambda-throttles" \
    "Throttles detected for Internet Lambda function" \
    "Throttles" \
    "AWS/Lambda" \
    "Sum" \
    "1" \
    "GreaterThanOrEqualToThreshold" \
    "1" \
    "300" \
    "Name=FunctionName,Value=$INTERNET_LAMBDA_NAME"

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-vpn-lambda-throttles" \
    "Throttles detected for VPN Lambda function" \
    "Throttles" \
    "AWS/Lambda" \
    "Sum" \
    "1" \
    "GreaterThanOrEqualToThreshold" \
    "1" \
    "300" \
    "Name=FunctionName,Value=$VPN_LAMBDA_NAME"

# 4. API Gateway Error Rate Alarms
log_info "Creating API Gateway error rate alarms..."

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-api-gateway-4xx-errors" \
    "High 4XX error rate for API Gateway" \
    "4XXError" \
    "AWS/ApiGateway" \
    "Sum" \
    "50" \
    "GreaterThanThreshold" \
    "2" \
    "300" \
    "Name=ApiName,Value=$API_GATEWAY_ID Name=Stage,Value=$API_GATEWAY_STAGE"

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-api-gateway-5xx-errors" \
    "High 5XX error rate for API Gateway" \
    "5XXError" \
    "AWS/ApiGateway" \
    "Sum" \
    "10" \
    "GreaterThanThreshold" \
    "2" \
    "300" \
    "Name=ApiName,Value=$API_GATEWAY_ID Name=Stage,Value=$API_GATEWAY_STAGE"

# 5. API Gateway Latency Alarms
log_info "Creating API Gateway latency alarms..."

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-api-gateway-high-latency" \
    "High latency for API Gateway" \
    "Latency" \
    "AWS/ApiGateway" \
    "Average" \
    "30000" \
    "GreaterThanThreshold" \
    "3" \
    "300" \
    "Name=ApiName,Value=$API_GATEWAY_ID Name=Stage,Value=$API_GATEWAY_STAGE"

# 6. Custom Dual Routing Alarms
log_info "Creating custom dual routing alarms..."

# VPN-specific error alarm
create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-vpn-specific-errors" \
    "VPN-specific errors detected" \
    "ErrorCount" \
    "CrossPartition/DualRouting/Errors" \
    "Sum" \
    "5" \
    "GreaterThanThreshold" \
    "2" \
    "300" \
    "Name=RoutingMethod,Value=vpn Name=ErrorCategory,Value=vpn_specific"

# Success rate alarms
create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-internet-low-success-rate" \
    "Low success rate for Internet routing" \
    "SuccessRatePercentage" \
    "CrossPartition/DualRouting/Analytics" \
    "Average" \
    "95" \
    "LessThanThreshold" \
    "3" \
    "300" \
    "Name=RoutingMethod,Value=internet"

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-vpn-low-success-rate" \
    "Low success rate for VPN routing" \
    "SuccessRatePercentage" \
    "CrossPartition/DualRouting/Analytics" \
    "Average" \
    "95" \
    "LessThanThreshold" \
    "3" \
    "300" \
    "Name=RoutingMethod,Value=vpn"

# VPC endpoint health alarms
create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-vpc-endpoint-secrets-unhealthy" \
    "Secrets Manager VPC endpoint unhealthy" \
    "VPCEndpointHealth" \
    "CrossPartition/DualRouting" \
    "Average" \
    "0.5" \
    "LessThanThreshold" \
    "2" \
    "300" \
    "Name=RoutingMethod,Value=vpn Name=EndpointName,Value=secrets"

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-vpc-endpoint-dynamodb-unhealthy" \
    "DynamoDB VPC endpoint unhealthy" \
    "VPCEndpointHealth" \
    "CrossPartition/DualRouting" \
    "Average" \
    "0.5" \
    "LessThanThreshold" \
    "2" \
    "300" \
    "Name=RoutingMethod,Value=vpn Name=EndpointName,Value=dynamodb"

create_alarm \
    "${PROJECT_NAME}-${ENVIRONMENT}-vpn-tunnel-down" \
    "VPN tunnel connection down" \
    "VPCEndpointHealth" \
    "CrossPartition/DualRouting" \
    "Average" \
    "0.5" \
    "LessThanThreshold" \
    "1" \
    "300" \
    "Name=RoutingMethod,Value=vpn Name=EndpointName,Value=vpn_tunnel"

# 7. Composite Alarms for Overall System Health
log_info "Creating composite alarms..."

# Create composite alarm for overall system health
aws cloudwatch put-composite-alarm \
    --alarm-name "${PROJECT_NAME}-${ENVIRONMENT}-system-health-critical" \
    --alarm-description "Critical system health issues detected" \
    --alarm-rule "ALARM(\"${PROJECT_NAME}-${ENVIRONMENT}-internet-lambda-high-errors\") OR ALARM(\"${PROJECT_NAME}-${ENVIRONMENT}-vpn-lambda-high-errors\") OR ALARM(\"${PROJECT_NAME}-${ENVIRONMENT}-api-gateway-5xx-errors\")" \
    --actions-enabled \
    $(if [[ -n "$SNS_TOPIC_ARN" ]]; then echo "--alarm-actions $SNS_TOPIC_ARN --ok-actions $SNS_TOPIC_ARN"; fi) \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION"

log_success "Created composite alarm: ${PROJECT_NAME}-${ENVIRONMENT}-system-health-critical"

# Create composite alarm for VPN-specific issues
aws cloudwatch put-composite-alarm \
    --alarm-name "${PROJECT_NAME}-${ENVIRONMENT}-vpn-health-warning" \
    --alarm-description "VPN routing health issues detected" \
    --alarm-rule "ALARM(\"${PROJECT_NAME}-${ENVIRONMENT}-vpn-specific-errors\") OR ALARM(\"${PROJECT_NAME}-${ENVIRONMENT}-vpc-endpoint-secrets-unhealthy\") OR ALARM(\"${PROJECT_NAME}-${ENVIRONMENT}-vpc-endpoint-dynamodb-unhealthy\") OR ALARM(\"${PROJECT_NAME}-${ENVIRONMENT}-vpn-tunnel-down\")" \
    --actions-enabled \
    $(if [[ -n "$SNS_TOPIC_ARN" ]]; then echo "--alarm-actions $SNS_TOPIC_ARN --ok-actions $SNS_TOPIC_ARN"; fi) \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION"

log_success "Created composite alarm: ${PROJECT_NAME}-${ENVIRONMENT}-vpn-health-warning"

log_success "All CloudWatch alarms created successfully!"
log_info ""
log_info "Created Alarms Summary:"
log_info "✓ Lambda function error rate alarms (Internet & VPN)"
log_info "✓ Lambda function duration alarms (Internet & VPN)"
log_info "✓ Lambda function throttle alarms (Internet & VPN)"
log_info "✓ API Gateway error rate alarms (4XX & 5XX)"
log_info "✓ API Gateway latency alarms"
log_info "✓ VPN-specific error alarms"
log_info "✓ Success rate alarms (Internet & VPN)"
log_info "✓ VPC endpoint health alarms"
log_info "✓ VPN tunnel health alarms"
log_info "✓ Composite system health alarms"
log_info ""
if [[ -n "$SNS_TOPIC_ARN" ]]; then
    log_info "Notifications will be sent to: $SNS_TOPIC_ARN"
    log_info ""
fi
log_info "Next steps:"
log_info "1. Configure SNS topic subscriptions (email, SMS, etc.)"
log_info "2. Test alarms by triggering conditions"
log_info "3. Adjust thresholds based on your requirements"
log_info "4. Set up escalation procedures for critical alarms"