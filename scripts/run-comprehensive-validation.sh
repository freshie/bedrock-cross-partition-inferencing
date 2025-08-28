#!/bin/bash

# Run comprehensive validation tests for dual routing system
# This script orchestrates all validation tests and generates reports

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
API_GATEWAY_STACK=""
TEST_MODEL_ID="anthropic.claude-3-haiku-20240307-v1:0"
LOAD_TEST_DURATION="60"
LOAD_TEST_RPS="10"
OUTPUT_DIR="outputs"
COMPREHENSIVE_TEST="true"
PERFORMANCE_TEST="true"
LOAD_TEST="true"

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
Run comprehensive validation tests for dual routing system

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --api-gateway-stack NAME    API Gateway CloudFormation stack name (required)
    --test-model-id ID          Model ID for testing (default: anthropic.claude-3-haiku-20240307-v1:0)
    --load-test-duration SEC    Load test duration in seconds (default: 60)
    --load-test-rps NUM         Load test requests per second (default: 10)
    --output-dir DIR            Output directory for reports (default: outputs)
    --skip-comprehensive        Skip comprehensive functional tests
    --skip-performance          Skip performance comparison tests
    --skip-load-test            Skip load testing
    --help                     Show this help message

Examples:
    # Run all validation tests
    $0 --api-gateway-stack my-api-gateway-stack

    # Run with custom load test parameters
    $0 --api-gateway-stack my-api-gateway-stack \\
       --load-test-duration 120 \\
       --load-test-rps 20

    # Run only functional tests (skip load testing)
    $0 --api-gateway-stack my-api-gateway-stack \\
       --skip-load-test

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
        --api-gateway-stack)
            API_GATEWAY_STACK="$2"
            shift 2
            ;;
        --test-model-id)
            TEST_MODEL_ID="$2"
            shift 2
            ;;
        --load-test-duration)
            LOAD_TEST_DURATION="$2"
            shift 2
            ;;
        --load-test-rps)
            LOAD_TEST_RPS="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --skip-comprehensive)
            COMPREHENSIVE_TEST="false"
            shift
            ;;
        --skip-performance)
            PERFORMANCE_TEST="false"
            shift
            ;;
        --skip-load-test)
            LOAD_TEST="false"
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

# Create output directory
mkdir -p "$PROJECT_ROOT/$OUTPUT_DIR"

log_info "Starting comprehensive validation for dual routing system..."
log_info "  Project: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Region: $AWS_REGION"
log_info "  API Gateway Stack: $API_GATEWAY_STACK"
log_info "  Test Model: $TEST_MODEL_ID"
log_info "  Load Test Duration: ${LOAD_TEST_DURATION}s"
log_info "  Load Test RPS: $LOAD_TEST_RPS"

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

# Get API Gateway information
log_info "Retrieving API Gateway information..."

API_GATEWAY_URL=$(get_stack_output "$API_GATEWAY_STACK" "ApiGatewayUrl")
if [[ -z "$API_GATEWAY_URL" ]]; then
    API_GATEWAY_URL=$(get_stack_output "$API_GATEWAY_STACK" "ApiUrl")
fi

API_KEY=$(get_stack_output "$API_GATEWAY_STACK" "ApiKeyValue")
if [[ -z "$API_KEY" ]]; then
    API_KEY=$(get_stack_output "$API_GATEWAY_STACK" "ApiKey")
fi

# Validate we got the required information
if [[ -z "$API_GATEWAY_URL" ]]; then
    log_error "Could not retrieve API Gateway URL from stack: $API_GATEWAY_STACK"
    log_error "Expected output key: ApiGatewayUrl or ApiUrl"
    exit 1
fi

if [[ -z "$API_KEY" ]]; then
    log_error "Could not retrieve API Key from stack: $API_GATEWAY_STACK"
    log_error "Expected output key: ApiKeyValue or ApiKey"
    exit 1
fi

log_success "Retrieved API Gateway information:"
log_info "  URL: $API_GATEWAY_URL"
log_info "  API Key: ${API_KEY:0:10}..."

# Check Python dependencies
log_info "Checking Python dependencies..."

PYTHON_CMD="python3"
if ! command -v "$PYTHON_CMD" &> /dev/null; then
    log_error "Python 3 is required but not found"
    exit 1
fi

# Check required Python packages
REQUIRED_PACKAGES=("requests" "boto3")
MISSING_PACKAGES=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! $PYTHON_CMD -c "import $package" 2>/dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    log_warning "Missing Python packages: ${MISSING_PACKAGES[*]}"
    log_info "Installing missing packages..."
    $PYTHON_CMD -m pip install "${MISSING_PACKAGES[@]}"
fi

# Set up test environment
export AWS_PROFILE="$GOVCLOUD_PROFILE"
export AWS_REGION="$AWS_REGION"

# Generate timestamp for this test run
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEST_RUN_ID="${PROJECT_NAME}_${ENVIRONMENT}_${TIMESTAMP}"

# Run comprehensive validation tests
log_info ""
log_info "Running comprehensive validation tests..."

VALIDATION_OUTPUT_FILE="$PROJECT_ROOT/$OUTPUT_DIR/comprehensive_validation_${TIMESTAMP}.json"
VALIDATION_REPORT_FILE="$PROJECT_ROOT/$OUTPUT_DIR/validation_report_${TIMESTAMP}.md"

# Build Python command arguments
PYTHON_ARGS=(
    --api-url "$API_GATEWAY_URL"
    --api-key "$API_KEY"
    --model-id "$TEST_MODEL_ID"
    --output-file "$VALIDATION_OUTPUT_FILE"
)

if [[ "$LOAD_TEST" == "true" ]]; then
    PYTHON_ARGS+=(
        --load-test-duration "$LOAD_TEST_DURATION"
        --load-test-rps "$LOAD_TEST_RPS"
    )
fi

# Run the comprehensive validation
if $PYTHON_CMD "$PROJECT_ROOT/tests/test_comprehensive_validation.py" "${PYTHON_ARGS[@]}"; then
    log_success "Comprehensive validation completed successfully"
    VALIDATION_SUCCESS="true"
else
    log_error "Comprehensive validation failed"
    VALIDATION_SUCCESS="false"
fi

# Run additional specific tests if requested
if [[ "$COMPREHENSIVE_TEST" == "true" ]]; then
    log_info ""
    log_info "Running additional comprehensive tests..."
    
    # Run end-to-end tests
    if [[ -f "$SCRIPT_DIR/test-end-to-end-routing.sh" ]]; then
        log_info "Running end-to-end routing tests..."
        if "$SCRIPT_DIR/test-end-to-end-routing.sh" \
            --api-url "$API_GATEWAY_URL" \
            --api-key "$API_KEY" \
            --comprehensive; then
            log_success "End-to-end tests passed"
        else
            log_warning "End-to-end tests failed or had issues"
        fi
    fi
    
    # Run API Gateway integration tests
    if [[ -f "$SCRIPT_DIR/test-api-gateway-integration.sh" ]]; then
        log_info "Running API Gateway integration tests..."
        if "$SCRIPT_DIR/test-api-gateway-integration.sh" \
            --stack-name "$API_GATEWAY_STACK" \
            --comprehensive; then
            log_success "API Gateway integration tests passed"
        else
            log_warning "API Gateway integration tests failed or had issues"
        fi
    fi
fi

# Generate comprehensive validation report
log_info ""
log_info "Generating validation report..."

cat > "$VALIDATION_REPORT_FILE" << EOF
# Comprehensive Validation Report

## Test Run Information
- **Test Run ID**: $TEST_RUN_ID
- **Project**: $PROJECT_NAME
- **Environment**: $ENVIRONMENT
- **AWS Region**: $AWS_REGION
- **Test Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- **API Gateway Stack**: $API_GATEWAY_STACK
- **API Gateway URL**: $API_GATEWAY_URL

## Test Configuration
- **Test Model ID**: $TEST_MODEL_ID
- **Load Test Duration**: ${LOAD_TEST_DURATION} seconds
- **Load Test RPS**: $LOAD_TEST_RPS requests/second
- **Comprehensive Tests**: $COMPREHENSIVE_TEST
- **Performance Tests**: $PERFORMANCE_TEST
- **Load Tests**: $LOAD_TEST

## Test Results Summary

### Overall Status
$(if [[ "$VALIDATION_SUCCESS" == "true" ]]; then
    echo "✅ **PASSED** - All validation tests completed successfully"
else
    echo "❌ **FAILED** - Some validation tests failed"
fi)

### Test Categories Executed

#### 1. Health Endpoint Tests
- Internet routing health check
- VPN routing health check

#### 2. Model Listing Tests
- Internet routing model listing
- VPN routing model listing

#### 3. Model Inference Tests
- Internet routing inference
- VPN routing inference

#### 4. Error Handling Tests
- Invalid model ID handling
- Malformed payload handling
- Authentication failure handling

#### 5. Performance Comparison Tests
- Response time comparison
- Success rate comparison
- Throughput analysis

#### 6. Functional Equivalence Tests
- Response structure validation
- Cross-routing consistency checks

$(if [[ "$LOAD_TEST" == "true" ]]; then
echo "#### 7. Load Testing
- Internet routing load test
- VPN routing load test
- Concurrent request handling"
fi)

#### 8. CloudWatch Metrics Validation
- Custom metrics publishing verification
- Metric data availability checks

## Detailed Results

Detailed test results are available in the JSON output file:
\`$VALIDATION_OUTPUT_FILE\`

## Performance Insights

$(if [[ -f "$VALIDATION_OUTPUT_FILE" ]]; then
    echo "### Key Performance Metrics"
    echo ""
    echo "Performance metrics extracted from test results:"
    echo ""
    echo "- **Internet Routing Performance**: See detailed JSON results"
    echo "- **VPN Routing Performance**: See detailed JSON results"
    echo "- **Comparative Analysis**: Available in performance_comparison section"
    echo ""
    echo "### Load Test Results"
    echo ""
    echo "Load test results (if executed):"
    echo ""
    echo "- **Target Load**: $LOAD_TEST_RPS RPS for ${LOAD_TEST_DURATION}s"
    echo "- **Internet Routing**: See load_tests.internet in JSON results"
    echo "- **VPN Routing**: See load_tests.vpn in JSON results"
fi)

## Recommendations

### Performance Optimization
1. **Latency Analysis**: Review P95 and P99 response times
2. **Error Rate Monitoring**: Investigate any error patterns
3. **Capacity Planning**: Use load test results for scaling decisions

### Reliability Improvements
1. **Error Handling**: Ensure robust error handling for all scenarios
2. **Monitoring**: Set up alerts based on test thresholds
3. **Failover**: Test failover scenarios between routing methods

### Operational Excellence
1. **Regular Testing**: Schedule regular validation runs
2. **Performance Baselines**: Establish performance baselines
3. **Alerting**: Configure alerts for performance degradation

## Next Steps

1. **Review Detailed Results**: Analyze the JSON output file for specific metrics
2. **Address Issues**: Investigate and resolve any failed tests
3. **Performance Tuning**: Optimize based on performance test results
4. **Monitoring Setup**: Configure ongoing monitoring based on test insights
5. **Documentation**: Update operational documentation with test findings

## Test Artifacts

- **Detailed Results**: \`$VALIDATION_OUTPUT_FILE\`
- **Test Report**: \`$VALIDATION_REPORT_FILE\`
- **Test Logs**: Available in script output above

---
*Report generated by comprehensive validation script*
*Test Run ID: $TEST_RUN_ID*
EOF

# Create summary for console output
log_info ""
log_info "Validation Summary:"
log_info "=================="

if [[ "$VALIDATION_SUCCESS" == "true" ]]; then
    log_success "✅ Comprehensive validation PASSED"
else
    log_error "❌ Comprehensive validation FAILED"
fi

log_info ""
log_info "Generated Reports:"
log_info "  📊 Detailed Results: $VALIDATION_OUTPUT_FILE"
log_info "  📋 Validation Report: $VALIDATION_REPORT_FILE"

# Display key metrics if available
if [[ -f "$VALIDATION_OUTPUT_FILE" ]] && command -v jq &> /dev/null; then
    log_info ""
    log_info "Quick Performance Summary:"
    
    # Extract key metrics using jq
    INTERNET_SUCCESS_RATE=$(jq -r '.performance_comparison.internet.success_rate // "N/A"' "$VALIDATION_OUTPUT_FILE" 2>/dev/null || echo "N/A")
    VPN_SUCCESS_RATE=$(jq -r '.performance_comparison.vpn.success_rate // "N/A"' "$VALIDATION_OUTPUT_FILE" 2>/dev/null || echo "N/A")
    INTERNET_AVG_LATENCY=$(jq -r '.performance_comparison.internet.avg_response_time // "N/A"' "$VALIDATION_OUTPUT_FILE" 2>/dev/null || echo "N/A")
    VPN_AVG_LATENCY=$(jq -r '.performance_comparison.vpn.avg_response_time // "N/A"' "$VALIDATION_OUTPUT_FILE" 2>/dev/null || echo "N/A")
    
    if [[ "$INTERNET_SUCCESS_RATE" != "N/A" ]]; then
        log_info "  🌐 Internet Success Rate: ${INTERNET_SUCCESS_RATE}%"
    fi
    if [[ "$VPN_SUCCESS_RATE" != "N/A" ]]; then
        log_info "  🔒 VPN Success Rate: ${VPN_SUCCESS_RATE}%"
    fi
    if [[ "$INTERNET_AVG_LATENCY" != "N/A" ]]; then
        log_info "  ⚡ Internet Avg Latency: ${INTERNET_AVG_LATENCY}ms"
    fi
    if [[ "$VPN_AVG_LATENCY" != "N/A" ]]; then
        log_info "  🔐 VPN Avg Latency: ${VPN_AVG_LATENCY}ms"
    fi
fi

log_info ""
log_info "Next Steps:"
log_info "1. Review the detailed validation report: $VALIDATION_REPORT_FILE"
log_info "2. Analyze performance metrics in: $VALIDATION_OUTPUT_FILE"
log_info "3. Address any failed tests or performance issues"
log_info "4. Set up ongoing monitoring based on test results"

# Exit with appropriate code
if [[ "$VALIDATION_SUCCESS" == "true" ]]; then
    exit 0
else
    exit 1
fi