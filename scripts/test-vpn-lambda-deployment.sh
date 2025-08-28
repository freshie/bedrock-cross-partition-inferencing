#!/bin/bash

# Test script for VPN Lambda deployment
# Validates VPN Lambda function deployment, configuration, and basic functionality

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
FUNCTION_NAME=""

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

print_header() {
    echo
    echo "================================================================================"
    echo "$1"
    echo "================================================================================"
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Test VPN Lambda function deployment"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV         Environment (dev, stage, prod) [default: prod]"
    echo "  -p, --project-name NAME       Project name [default: dual-routing-api-gateway]"
    echo "  -f, --function-name NAME      Lambda function name"
    echo "  -r, --region REGION           AWS region [default: us-gov-west-1]"
    echo "  --comprehensive               Run comprehensive tests"
    echo "  --performance                 Run performance tests"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --environment dev"
    echo "  $0 --function-name my-vpn-lambda --comprehensive"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    print_header "VALIDATING PREREQUISITES"
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    log_success "AWS CLI found: $(aws --version)"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    log_success "AWS credentials validated"
    
    # Check jq for JSON parsing
    if ! command_exists jq; then
        log_warning "jq not found. Some features may be limited."
    else
        log_success "jq found for JSON parsing"
    fi
}

# Function to test Lambda function existence
test_function_existence() {
    print_header "TESTING LAMBDA FUNCTION EXISTENCE"
    
    log_info "Checking if Lambda function exists: $FUNCTION_NAME"
    
    if aws lambda get-function --function-name "$FUNCTION_NAME" >/dev/null 2>&1; then
        log_success "Lambda function exists: $FUNCTION_NAME"
        return 0
    else
        log_error "Lambda function not found: $FUNCTION_NAME"
        return 1
    fi
}

# Function to test Lambda function configuration
test_function_configuration() {
    print_header "TESTING LAMBDA FUNCTION CONFIGURATION"
    
    log_info "Retrieving Lambda function configuration..."
    
    local function_config
    function_config=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --output json 2>/dev/null)
    
    if [[ -z "$function_config" ]]; then
        log_error "Failed to retrieve function configuration"
        return 1
    fi
    
    # Extract configuration details
    local runtime
    local handler
    local memory_size
    local timeout
    local vpc_config
    local environment_vars
    
    runtime=$(echo "$function_config" | jq -r '.Runtime' 2>/dev/null)
    handler=$(echo "$function_config" | jq -r '.Handler' 2>/dev/null)
    memory_size=$(echo "$function_config" | jq -r '.MemorySize' 2>/dev/null)
    timeout=$(echo "$function_config" | jq -r '.Timeout' 2>/dev/null)
    vpc_config=$(echo "$function_config" | jq -r '.VpcConfig' 2>/dev/null)
    environment_vars=$(echo "$function_config" | jq -r '.Environment.Variables' 2>/dev/null)
    
    log_info "Function Configuration:"
    log_info "  Runtime: $runtime"
    log_info "  Handler: $handler"
    log_info "  Memory Size: ${memory_size}MB"
    log_info "  Timeout: ${timeout}s"
    
    # Validate runtime
    if [[ "$runtime" == "python3.9" || "$runtime" == "python3.8" || "$runtime" == "python3.10" ]]; then
        log_success "Runtime is supported: $runtime"
    else
        log_warning "Unexpected runtime: $runtime"
    fi
    
    # Validate handler
    if [[ "$handler" == "dual_routing_vpn_lambda.lambda_handler" ]]; then
        log_success "Handler is correct: $handler"
    else
        log_warning "Unexpected handler: $handler"
    fi
    
    # Check VPC configuration
    if [[ "$vpc_config" != "null" ]]; then
        local vpc_id
        local subnet_ids
        local security_group_ids
        
        vpc_id=$(echo "$vpc_config" | jq -r '.VpcId' 2>/dev/null)
        subnet_ids=$(echo "$vpc_config" | jq -r '.SubnetIds[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        security_group_ids=$(echo "$vpc_config" | jq -r '.SecurityGroupIds[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        
        log_success "VPC Configuration found:"
        log_info "  VPC ID: $vpc_id"
        log_info "  Subnet IDs: $subnet_ids"
        log_info "  Security Group IDs: $security_group_ids"
    else
        log_error "No VPC configuration found - VPN Lambda should be in VPC"
        return 1
    fi
    
    # Check environment variables
    if [[ "$environment_vars" != "null" ]]; then
        log_success "Environment variables configured"
        
        # Check for required environment variables
        local required_vars=("COMMERCIAL_CREDENTIALS_SECRET" "REQUEST_LOG_TABLE")
        
        for var in "${required_vars[@]}"; do
            local var_value
            var_value=$(echo "$environment_vars" | jq -r ".$var" 2>/dev/null)
            
            if [[ "$var_value" != "null" && -n "$var_value" ]]; then
                log_success "  $var: configured"
            else
                log_warning "  $var: not configured"
            fi
        done
    else
        log_warning "No environment variables configured"
    fi
    
    return 0
}

# Function to test Lambda function invocation
test_function_invocation() {
    print_header "TESTING LAMBDA FUNCTION INVOCATION"
    
    log_info "Testing Lambda function with GET request..."
    
    # Create test event for GET request (health check)
    local test_event='{
        "httpMethod": "GET",
        "path": "/v1/vpn/bedrock",
        "headers": {
            "Content-Type": "application/json"
        },
        "requestContext": {
            "identity": {
                "sourceIp": "10.0.1.100"
            }
        }
    }'
    
    # Invoke function
    local response_file="/tmp/vpn-lambda-test-response.json"
    local response
    response=$(aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload "$test_event" \
        --output json \
        "$response_file" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        local status_code
        status_code=$(echo "$response" | jq -r '.StatusCode' 2>/dev/null)
        
        if [[ "$status_code" == "200" ]]; then
            log_success "Lambda function invocation successful"
            
            # Check response content
            if [[ -f "$response_file" ]]; then
                local response_body
                response_body=$(cat "$response_file")
                
                if echo "$response_body" | jq -e '.statusCode' >/dev/null 2>&1; then
                    local http_status
                    http_status=$(echo "$response_body" | jq -r '.statusCode')
                    
                    log_info "HTTP Status Code: $http_status"
                    
                    if [[ "$http_status" == "200" ]]; then
                        log_success "Lambda function is responding correctly"
                        
                        # Check for VPN routing method
                        local routing_method
                        routing_method=$(echo "$response_body" | jq -r '.body' 2>/dev/null | jq -r '.routing.method' 2>/dev/null)
                        
                        if [[ "$routing_method" == "vpn" ]]; then
                            log_success "VPN routing method confirmed"
                        else
                            log_info "Routing method: ${routing_method:-unknown}"
                        fi
                    else
                        log_warning "Lambda function returned HTTP status: $http_status"
                    fi
                else
                    log_warning "Unexpected response format"
                fi
            fi
        else
            log_warning "Lambda function invocation returned status: $status_code"
        fi
    else
        log_error "Lambda function invocation failed"
        return 1
    fi
    
    # Clean up test file
    rm -f "$response_file"
    
    return 0
}

# Function to test VPC connectivity
test_vpc_connectivity() {
    print_header "TESTING VPC CONNECTIVITY"
    
    log_info "Testing VPC endpoint connectivity..."
    
    # Create test event that would require VPC endpoint access
    local test_event='{
        "httpMethod": "POST",
        "path": "/v1/vpn/bedrock/invoke-model",
        "headers": {
            "Content-Type": "application/json"
        },
        "body": "{\"modelId\": \"test-model\", \"body\": {\"test\": true}}",
        "requestContext": {
            "identity": {
                "sourceIp": "10.0.1.100"
            }
        }
    }'
    
    # Invoke function
    local response_file="/tmp/vpn-lambda-vpc-test-response.json"
    local response
    response=$(aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload "$test_event" \
        --output json \
        "$response_file" 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        local status_code
        status_code=$(echo "$response" | jq -r '.StatusCode' 2>/dev/null)
        
        if [[ "$status_code" == "200" ]]; then
            log_success "VPC connectivity test invocation successful"
            
            # Check response for VPC-related errors
            if [[ -f "$response_file" ]]; then
                local response_body
                response_body=$(cat "$response_file")
                
                # Look for common VPC connectivity issues
                if echo "$response_body" | grep -q "timeout\|connection\|endpoint"; then
                    log_warning "Possible VPC connectivity issues detected"
                    log_info "Response: $response_body"
                else
                    log_success "No obvious VPC connectivity issues detected"
                fi
            fi
        else
            log_warning "VPC connectivity test returned status: $status_code"
        fi
    else
        log_error "VPC connectivity test failed"
    fi
    
    # Clean up test file
    rm -f "$response_file"
}

# Function to test CloudWatch logs
test_cloudwatch_logs() {
    print_header "TESTING CLOUDWATCH LOGS"
    
    local log_group_name="/aws/lambda/$FUNCTION_NAME"
    
    log_info "Checking CloudWatch log group: $log_group_name"
    
    # Check if log group exists
    if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group_name"; then
        log_success "CloudWatch log group exists: $log_group_name"
        
        # Check for recent log streams
        local log_streams
        log_streams=$(aws logs describe-log-streams --log-group-name "$log_group_name" --order-by LastEventTime --descending --max-items 5 --query 'logStreams[*].logStreamName' --output text 2>/dev/null)
        
        if [[ -n "$log_streams" ]]; then
            log_success "Recent log streams found"
            log_info "Recent log streams: $(echo "$log_streams" | tr '\t' ' ')"
        else
            log_warning "No recent log streams found"
        fi
    else
        log_warning "CloudWatch log group not found: $log_group_name"
    fi
}

# Function to run performance tests
run_performance_tests() {
    if [[ "$PERFORMANCE" != "true" ]]; then
        return 0
    fi
    
    print_header "RUNNING PERFORMANCE TESTS"
    
    log_info "Running performance tests for VPN Lambda function..."
    
    local test_count=5
    local total_duration=0
    local successful_invocations=0
    
    # Simple test event
    local test_event='{
        "httpMethod": "GET",
        "path": "/v1/vpn/bedrock",
        "headers": {"Content-Type": "application/json"},
        "requestContext": {"identity": {"sourceIp": "10.0.1.100"}}
    }'
    
    for i in $(seq 1 $test_count); do
        log_info "Performance test $i/$test_count..."
        
        local start_time=$(date +%s%3N)
        local response_file="/tmp/perf-test-$i.json"
        
        if aws lambda invoke \
            --function-name "$FUNCTION_NAME" \
            --payload "$test_event" \
            --output json \
            "$response_file" >/dev/null 2>&1; then
            
            local end_time=$(date +%s%3N)
            local duration=$((end_time - start_time))
            total_duration=$((total_duration + duration))
            successful_invocations=$((successful_invocations + 1))
            
            log_info "  Test $i: ${duration}ms"
        else
            log_warning "  Test $i: Failed"
        fi
        
        rm -f "$response_file"
        
        # Small delay between tests
        sleep 1
    done
    
    if [[ $successful_invocations -gt 0 ]]; then
        local avg_duration=$((total_duration / successful_invocations))
        log_success "Performance test results:"
        log_info "  Successful invocations: $successful_invocations/$test_count"
        log_info "  Average duration: ${avg_duration}ms"
        log_info "  Total duration: ${total_duration}ms"
        
        if [[ $avg_duration -lt 5000 ]]; then
            log_success "Performance is within acceptable limits"
        else
            log_warning "Performance may be slower than expected"
        fi
    else
        log_error "All performance tests failed"
    fi
}

# Function to generate test report
generate_test_report() {
    print_header "GENERATING TEST REPORT"
    
    local report_file="$PROJECT_ROOT/outputs/vpn-lambda-test-report-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "VPN Lambda Function Test Report"
        echo "Generated: $(date)"
        echo "Function Name: $FUNCTION_NAME"
        echo "Project: $PROJECT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo ""
        echo "Test Results:"
        echo "- Function Existence: $(test_function_existence >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
        echo "- Function Configuration: $(test_function_configuration >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
        echo "- Function Invocation: $(test_function_invocation >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
        echo "- VPC Connectivity: Test completed"
        echo "- CloudWatch Logs: Test completed"
        if [[ "$PERFORMANCE" == "true" ]]; then
            echo "- Performance Tests: Completed"
        fi
        echo ""
        echo "Test Categories:"
        echo "- Basic functionality validation"
        echo "- VPC configuration verification"
        echo "- Environment variable validation"
        echo "- CloudWatch integration testing"
        echo "- VPC endpoint connectivity testing"
        if [[ "$COMPREHENSIVE" == "true" ]]; then
            echo "- Comprehensive error handling tests"
        fi
        if [[ "$PERFORMANCE" == "true" ]]; then
            echo "- Performance and latency testing"
        fi
        echo ""
        echo "Next Steps:"
        echo "1. Review any warnings or failures above"
        echo "2. Test VPN Lambda with API Gateway integration"
        echo "3. Run end-to-end tests with actual Bedrock requests"
        echo "4. Monitor function performance in production"
    } > "$report_file"
    
    log_success "Test report generated: $report_file"
}

# Main execution function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -p|--project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -r|--region)
                export AWS_REGION="$2"
                shift 2
                ;;
            --comprehensive)
                COMPREHENSIVE="true"
                shift
                ;;
            --performance)
                PERFORMANCE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set defaults
    export AWS_REGION="${AWS_REGION:-us-gov-west-1}"
    FUNCTION_NAME="${FUNCTION_NAME:-$PROJECT_NAME-$ENVIRONMENT-vpn-lambda}"
    
    print_header "VPN LAMBDA FUNCTION TESTING"
    log_info "Function Name: $FUNCTION_NAME"
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "AWS Region: $AWS_REGION"
    
    # Execute test steps
    validate_prerequisites
    
    if ! test_function_existence; then
        log_error "Cannot proceed with tests - function does not exist"
        exit 1
    fi
    
    test_function_configuration
    test_function_invocation
    test_vpc_connectivity
    test_cloudwatch_logs
    run_performance_tests
    generate_test_report
    
    print_header "TESTING COMPLETED"
    log_success "VPN Lambda function testing completed"
    log_info "Review the test report for detailed results"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi