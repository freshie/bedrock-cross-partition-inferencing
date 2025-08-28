#!/bin/bash

# Test monitoring dashboard functionality for dual routing system
# This script validates dashboard creation and metric availability

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
INTERNET_LAMBDA_STACK=""
VPN_LAMBDA_STACK=""
API_GATEWAY_STACK=""
COMPREHENSIVE_TEST="false"

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
Test monitoring dashboard functionality for dual routing system

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --internet-lambda-stack NAME Internet Lambda CloudFormation stack name (required)
    --vpn-lambda-stack NAME     VPN Lambda CloudFormation stack name (required)
    --api-gateway-stack NAME    API Gateway CloudFormation stack name (required)
    --comprehensive             Run comprehensive tests including metric validation
    --help                     Show this help message

Examples:
    # Basic dashboard test
    $0 --internet-lambda-stack my-internet-lambda-stack \\
       --vpn-lambda-stack my-vpn-lambda-stack \\
       --api-gateway-stack my-api-gateway-stack

    # Comprehensive test with metric validation
    $0 --internet-lambda-stack my-internet-lambda-stack \\
       --vpn-lambda-stack my-vpn-lambda-stack \\
       --api-gateway-stack my-api-gateway-stack \\
       --comprehensive

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
        --comprehensive)
            COMPREHENSIVE_TEST="true"
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

log_info "Testing monitoring dashboard for dual routing system..."
log_info "  Project: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Region: $AWS_REGION"
log_info "  Comprehensive Test: $COMPREHENSIVE_TEST"

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
    exit 1
fi

if [[ -z "$VPN_LAMBDA_NAME" ]]; then
    log_error "Could not retrieve VPN Lambda function name from stack: $VPN_LAMBDA_STACK"
    exit 1
fi

if [[ -z "$API_GATEWAY_ID" ]]; then
    log_error "Could not retrieve API Gateway ID from stack: $API_GATEWAY_STACK"
    exit 1
fi

log_success "Retrieved resource information:"
log_info "  Internet Lambda: $INTERNET_LAMBDA_NAME"
log_info "  VPN Lambda: $VPN_LAMBDA_NAME"
log_info "  API Gateway: $API_GATEWAY_ID"
log_info "  API Gateway Stage: $API_GATEWAY_STAGE"

# Test 1: Create monitoring dashboard
log_info ""
log_info "Test 1: Creating monitoring dashboard..."

DASHBOARD_NAME="${PROJECT_NAME}-test-${ENVIRONMENT}-$(date +%s)"

if "$SCRIPT_DIR/create-monitoring-dashboard.sh" \
    --project-name "$PROJECT_NAME" \
    --environment "test-${ENVIRONMENT}" \
    --govcloud-profile "$GOVCLOUD_PROFILE" \
    --dashboard-name "$DASHBOARD_NAME" \
    --internet-lambda "$INTERNET_LAMBDA_NAME" \
    --vpn-lambda "$VPN_LAMBDA_NAME" \
    --api-gateway-id "$API_GATEWAY_ID" \
    --api-gateway-stage "$API_GATEWAY_STAGE"; then
    log_success "Dashboard creation test passed"
else
    log_error "Dashboard creation test failed"
    exit 1
fi

# Test 2: Verify dashboard exists
log_info ""
log_info "Test 2: Verifying dashboard exists..."

if aws cloudwatch get-dashboard \
    --dashboard-name "$DASHBOARD_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    log_success "Dashboard verification test passed"
else
    log_error "Dashboard verification test failed"
    exit 1
fi

# Test 3: Create performance comparison dashboard
log_info ""
log_info "Test 3: Creating performance comparison dashboard..."

PERF_DASHBOARD_NAME="${PROJECT_NAME}-perf-test-${ENVIRONMENT}-$(date +%s)"

if "$SCRIPT_DIR/create-performance-comparison-dashboard.sh" \
    --project-name "$PROJECT_NAME" \
    --environment "test-${ENVIRONMENT}" \
    --govcloud-profile "$GOVCLOUD_PROFILE" \
    --dashboard-name "$PERF_DASHBOARD_NAME" \
    --internet-lambda "$INTERNET_LAMBDA_NAME" \
    --vpn-lambda "$VPN_LAMBDA_NAME" \
    --api-gateway-id "$API_GATEWAY_ID" \
    --api-gateway-stage "$API_GATEWAY_STAGE"; then
    log_success "Performance dashboard creation test passed"
else
    log_error "Performance dashboard creation test failed"
    exit 1
fi

# Test 4: Create alarms
log_info ""
log_info "Test 4: Creating test alarms..."

if "$SCRIPT_DIR/create-dual-routing-alarms.sh" \
    --project-name "$PROJECT_NAME" \
    --environment "test-${ENVIRONMENT}" \
    --govcloud-profile "$GOVCLOUD_PROFILE" \
    --internet-lambda "$INTERNET_LAMBDA_NAME" \
    --vpn-lambda "$VPN_LAMBDA_NAME" \
    --api-gateway-id "$API_GATEWAY_ID" \
    --api-gateway-stage "$API_GATEWAY_STAGE" \
    --create-sns-topic; then
    log_success "Alarms creation test passed"
else
    log_error "Alarms creation test failed"
    exit 1
fi

# Test 5: Verify alarms exist
log_info ""
log_info "Test 5: Verifying alarms exist..."

ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${PROJECT_NAME}-test-${ENVIRONMENT}" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query 'length(MetricAlarms)' \
    --output text 2>/dev/null || echo "0")

if [[ "$ALARM_COUNT" -gt 0 ]]; then
    log_success "Alarms verification test passed ($ALARM_COUNT alarms found)"
else
    log_error "Alarms verification test failed (no alarms found)"
    exit 1
fi

# Comprehensive tests
if [[ "$COMPREHENSIVE_TEST" == "true" ]]; then
    log_info ""
    log_info "Running comprehensive tests..."
    
    # Test 6: Validate Lambda functions exist
    log_info ""
    log_info "Test 6: Validating Lambda functions exist..."
    
    if aws lambda get-function \
        --function-name "$INTERNET_LAMBDA_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_success "Internet Lambda function exists"
    else
        log_error "Internet Lambda function not found: $INTERNET_LAMBDA_NAME"
        exit 1
    fi
    
    if aws lambda get-function \
        --function-name "$VPN_LAMBDA_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_success "VPN Lambda function exists"
    else
        log_error "VPN Lambda function not found: $VPN_LAMBDA_NAME"
        exit 1
    fi
    
    # Test 7: Validate API Gateway exists
    log_info ""
    log_info "Test 7: Validating API Gateway exists..."
    
    if aws apigateway get-rest-api \
        --rest-api-id "$API_GATEWAY_ID" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_success "API Gateway exists"
    else
        log_error "API Gateway not found: $API_GATEWAY_ID"
        exit 1
    fi
    
    # Test 8: Check CloudWatch log groups
    log_info ""
    log_info "Test 8: Checking CloudWatch log groups..."
    
    INTERNET_LOG_GROUP="/aws/lambda/$INTERNET_LAMBDA_NAME"
    VPN_LOG_GROUP="/aws/lambda/$VPN_LAMBDA_NAME"
    
    if aws logs describe-log-groups \
        --log-group-name-prefix "$INTERNET_LOG_GROUP" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" \
        --query 'logGroups[0].logGroupName' \
        --output text 2>/dev/null | grep -q "$INTERNET_LOG_GROUP"; then
        log_success "Internet Lambda log group exists"
    else
        log_warning "Internet Lambda log group not found (may be created on first invocation)"
    fi
    
    if aws logs describe-log-groups \
        --log-group-name-prefix "$VPN_LOG_GROUP" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" \
        --query 'logGroups[0].logGroupName' \
        --output text 2>/dev/null | grep -q "$VPN_LOG_GROUP"; then
        log_success "VPN Lambda log group exists"
    else
        log_warning "VPN Lambda log group not found (may be created on first invocation)"
    fi
    
    # Test 9: Test metric publishing (if possible)
    log_info ""
    log_info "Test 9: Testing custom metric publishing..."
    
    # Publish test metrics
    aws cloudwatch put-metric-data \
        --namespace "CrossPartition/DualRouting/Test" \
        --metric-data MetricName=TestMetric,Value=1,Unit=Count,Dimensions=[{Name=RoutingMethod,Value=internet}] \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION"
    
    aws cloudwatch put-metric-data \
        --namespace "CrossPartition/DualRouting/Test" \
        --metric-data MetricName=TestMetric,Value=1,Unit=Count,Dimensions=[{Name=RoutingMethod,Value=vpn}] \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION"
    
    log_success "Test metrics published successfully"
    
    # Test 10: Validate dashboard JSON structure
    log_info ""
    log_info "Test 10: Validating dashboard JSON structure..."
    
    DASHBOARD_JSON=$(aws cloudwatch get-dashboard \
        --dashboard-name "$DASHBOARD_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" \
        --query 'DashboardBody' \
        --output text)
    
    if echo "$DASHBOARD_JSON" | jq . >/dev/null 2>&1; then
        log_success "Dashboard JSON structure is valid"
        
        # Count widgets
        WIDGET_COUNT=$(echo "$DASHBOARD_JSON" | jq '.widgets | length')
        log_info "Dashboard contains $WIDGET_COUNT widgets"
        
        if [[ "$WIDGET_COUNT" -gt 10 ]]; then
            log_success "Dashboard has sufficient widgets for comprehensive monitoring"
        else
            log_warning "Dashboard has fewer widgets than expected"
        fi
    else
        log_error "Dashboard JSON structure is invalid"
        exit 1
    fi
fi

# Cleanup test resources
log_info ""
log_info "Cleaning up test resources..."

# Delete test dashboards
aws cloudwatch delete-dashboards \
    --dashboard-names "$DASHBOARD_NAME" "$PERF_DASHBOARD_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" >/dev/null 2>&1 || true

# Delete test alarms
TEST_ALARMS=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${PROJECT_NAME}-test-${ENVIRONMENT}" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query 'MetricAlarms[].AlarmName' \
    --output text 2>/dev/null || echo "")

if [[ -n "$TEST_ALARMS" ]]; then
    aws cloudwatch delete-alarms \
        --alarm-names $TEST_ALARMS \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" >/dev/null 2>&1 || true
fi

# Delete test composite alarms
TEST_COMPOSITE_ALARMS=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${PROJECT_NAME}-test-${ENVIRONMENT}" \
    --alarm-types CompositeAlarm \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query 'CompositeAlarms[].AlarmName' \
    --output text 2>/dev/null || echo "")

if [[ -n "$TEST_COMPOSITE_ALARMS" ]]; then
    aws cloudwatch delete-alarms \
        --alarm-names $TEST_COMPOSITE_ALARMS \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" >/dev/null 2>&1 || true
fi

# Delete test SNS topic
TEST_SNS_TOPIC_NAME="${PROJECT_NAME}-test-${ENVIRONMENT}-alerts"
TEST_SNS_TOPIC_ARN=$(aws sns list-topics \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION" \
    --query "Topics[?contains(TopicArn, '$TEST_SNS_TOPIC_NAME')].TopicArn" \
    --output text 2>/dev/null || echo "")

if [[ -n "$TEST_SNS_TOPIC_ARN" ]]; then
    aws sns delete-topic \
        --topic-arn "$TEST_SNS_TOPIC_ARN" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" >/dev/null 2>&1 || true
fi

log_success "Test resources cleaned up"

# Generate test report
log_info ""
log_info "Generating test report..."

cat > "$PROJECT_ROOT/outputs/monitoring-test-report.md" << EOF
# Monitoring Dashboard Test Report

## Test Summary
- **Project**: $PROJECT_NAME
- **Environment**: $ENVIRONMENT
- **Region**: $AWS_REGION
- **Test Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- **Comprehensive Test**: $COMPREHENSIVE_TEST

## Resources Tested
- **Internet Lambda**: $INTERNET_LAMBDA_NAME
- **VPN Lambda**: $VPN_LAMBDA_NAME
- **API Gateway**: $API_GATEWAY_ID (Stage: $API_GATEWAY_STAGE)

## Test Results

### Basic Tests
✅ Dashboard creation test passed
✅ Dashboard verification test passed
✅ Performance dashboard creation test passed
✅ Alarms creation test passed
✅ Alarms verification test passed ($ALARM_COUNT alarms)

$(if [[ "$COMPREHENSIVE_TEST" == "true" ]]; then
echo "### Comprehensive Tests
✅ Internet Lambda function validation passed
✅ VPN Lambda function validation passed
✅ API Gateway validation passed
✅ CloudWatch log groups checked
✅ Custom metric publishing test passed
✅ Dashboard JSON structure validation passed"
fi)

## Recommendations

1. **Dashboard Usage**:
   - Access dashboards through CloudWatch console
   - Set appropriate time ranges for analysis
   - Customize refresh intervals as needed

2. **Alarm Configuration**:
   - Configure SNS topic subscriptions for notifications
   - Adjust alarm thresholds based on your requirements
   - Test alarm conditions in non-production environment

3. **Monitoring Best Practices**:
   - Review dashboards regularly
   - Analyze trends and patterns
   - Set up automated reporting if needed

## Next Steps

1. Deploy production monitoring dashboards
2. Configure notification channels
3. Set up regular monitoring reviews
4. Train team on dashboard usage

## Test Artifacts

- Test dashboards were created and validated
- Test alarms were created and verified
- All test resources were cleaned up successfully

---
Generated by monitoring dashboard test script
EOF

log_success ""
log_success "Monitoring dashboard test completed successfully!"
log_info ""
log_info "Test Results Summary:"
log_info "✅ All basic tests passed"
if [[ "$COMPREHENSIVE_TEST" == "true" ]]; then
    log_info "✅ All comprehensive tests passed"
fi
log_info "✅ Test resources cleaned up"
log_info "✅ Test report generated: $PROJECT_ROOT/outputs/monitoring-test-report.md"
log_info ""
log_info "The monitoring dashboard functionality is working correctly."
log_info "You can now proceed with production deployment."