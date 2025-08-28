#!/bin/bash

# Test script for API Gateway dual routing deployment
# Validates API Gateway configuration, endpoints, and routing functionality

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
STACK_NAME=""
API_GATEWAY_ID=""
API_KEY=""

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
    echo "Test API Gateway dual routing deployment"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV         Environment (dev, stage, prod) [default: prod]"
    echo "  -p, --project-name NAME       Project name [default: dual-routing-api-gateway]"
    echo "  -s, --stack-name STACK        CloudFormation stack name"
    echo "  -a, --api-gateway-id ID       API Gateway ID to test"
    echo "  -k, --api-key KEY             API key for testing"
    echo "  -r, --region REGION           AWS region [default: us-gov-west-1]"
    echo "  --aws-profile PROFILE         AWS CLI profile (optional)"
    echo "  --comprehensive               Run comprehensive tests"
    echo "  --load-test                   Run load testing"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --environment dev"
    echo "  $0 --stack-name dual-routing-api-gateway-prod-api-gateway"
    echo "  $0 --api-gateway-id abc123def456 --api-key your-api-key-here"
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
    if [[ -n "$AWS_PROFILE" ]]; then
        if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
            log_error "AWS credentials not configured or invalid for profile: $AWS_PROFILE"
            exit 1
        fi
    else
        if ! aws sts get-caller-identity >/dev/null 2>&1; then
            log_error "AWS credentials not configured or invalid."
            exit 1
        fi
    fi
    
    log_success "AWS credentials validated"
    
    # Check curl for endpoint testing
    if ! command_exists curl; then
        log_warning "curl not found. Endpoint testing will be limited."
    else
        log_success "curl found for endpoint testing"
    fi
    
    # Check jq for JSON parsing
    if ! command_exists jq; then
        log_warning "jq not found. JSON parsing will be limited."
    else
        log_success "jq found for JSON parsing"
    fi
}

# Function to run AWS CLI commands with optional profile
aws_cmd() {
    if [[ -n "$AWS_PROFILE" ]]; then
        aws --profile "$AWS_PROFILE" --region "${AWS_REGION:-us-gov-west-1}" "$@"
    else
        aws --region "${AWS_REGION:-us-gov-west-1}" "$@"
    fi
}

# Function to get API Gateway details from CloudFormation stack
get_api_gateway_from_stack() {
    local stack_name="$1"
    
    log_info "Getting API Gateway details from CloudFormation stack: $stack_name"
    
    # Check if stack exists
    if ! aws_cmd cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1; then
        log_error "CloudFormation stack not found: $stack_name"
        return 1
    fi
    
    # Get stack outputs
    local outputs
    outputs=$(aws_cmd cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].Outputs' --output json 2>/dev/null)
    
    if [[ "$outputs" != "null" && "$outputs" != "[]" ]]; then
        if command_exists jq; then
            API_GATEWAY_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="ApiGatewayId") | .OutputValue' 2>/dev/null)
            API_GATEWAY_URL=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="ApiGatewayUrl") | .OutputValue' 2>/dev/null)
            INTERNET_ENDPOINT=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="InternetEndpoint") | .OutputValue' 2>/dev/null)
            VPN_ENDPOINT=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNEndpoint") | .OutputValue' 2>/dev/null)
            INTERNET_MODELS_ENDPOINT=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="InternetModelsEndpoint") | .OutputValue' 2>/dev/null)
            VPN_MODELS_ENDPOINT=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNModelsEndpoint") | .OutputValue' 2>/dev/null)
            API_KEY_VALUE=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="ApiKeyValue") | .OutputValue' 2>/dev/null)
            
            log_success "Retrieved API Gateway details from stack:"
            log_info "  API Gateway ID: ${API_GATEWAY_ID:-not found}"
            log_info "  API Gateway URL: ${API_GATEWAY_URL:-not found}"
            log_info "  Internet Endpoint: ${INTERNET_ENDPOINT:-not found}"
            log_info "  VPN Endpoint: ${VPN_ENDPOINT:-not found}"
            log_info "  API Key: ${API_KEY_VALUE:-not created}"
            
            # Use discovered API key if not provided
            if [[ -z "$API_KEY" && -n "$API_KEY_VALUE" && "$API_KEY_VALUE" != "null" ]]; then
                API_KEY="$API_KEY_VALUE"
            fi
            
            return 0
        else
            log_warning "jq not available - cannot parse stack outputs"
            return 1
        fi
    else
        log_error "No outputs found in CloudFormation stack"
        return 1
    fi
}

# Function to test API Gateway configuration
test_api_gateway_configuration() {
    print_header "TESTING API GATEWAY CONFIGURATION"
    
    if [[ -z "$API_GATEWAY_ID" ]]; then
        log_warning "API Gateway ID not provided, skipping configuration tests"
        return 0
    fi
    
    log_info "Testing API Gateway configuration: $API_GATEWAY_ID"
    
    # Get API Gateway details
    local api_info
    api_info=$(aws_cmd apigateway get-rest-api --rest-api-id "$API_GATEWAY_ID" --output json 2>/dev/null)
    
    if [[ -n "$api_info" ]]; then
        if command_exists jq; then
            local api_name
            local api_description
            local endpoint_type
            
            api_name=$(echo "$api_info" | jq -r '.name' 2>/dev/null)
            api_description=$(echo "$api_info" | jq -r '.description' 2>/dev/null)
            endpoint_type=$(echo "$api_info" | jq -r '.endpointConfiguration.types[0]' 2>/dev/null)
            
            log_success "API Gateway configuration:"
            log_info "  Name: $api_name"
            log_info "  Description: $api_description"
            log_info "  Endpoint Type: $endpoint_type"
        else
            log_success "API Gateway exists and is accessible"
        fi
    else
        log_error "Could not retrieve API Gateway information"
        return 1
    fi
    
    # Test API Gateway resources
    log_info "Testing API Gateway resources..."
    local resources
    resources=$(aws_cmd apigateway get-resources --rest-api-id "$API_GATEWAY_ID" --output json 2>/dev/null)
    
    if [[ -n "$resources" ]]; then
        if command_exists jq; then
            local resource_count
            resource_count=$(echo "$resources" | jq '.items | length' 2>/dev/null)
            log_success "API Gateway has $resource_count resources configured"
            
            # Check for expected paths
            local expected_paths=(
                "/v1"
                "/v1/bedrock"
                "/v1/bedrock/invoke-model"
                "/v1/bedrock/models"
                "/v1/vpn"
                "/v1/vpn/bedrock"
                "/v1/vpn/bedrock/invoke-model"
                "/v1/vpn/bedrock/models"
            )
            
            for path in "${expected_paths[@]}"; do
                if echo "$resources" | jq -e ".items[] | select(.pathPart==\"${path##*/}\")" >/dev/null 2>&1; then
                    log_success "  Resource found: $path"
                else
                    log_warning "  Resource missing: $path"
                fi
            done
        else
            log_success "API Gateway resources are configured"
        fi
    else
        log_error "Could not retrieve API Gateway resources"
        return 1
    fi
    
    return 0
}

# Function to test endpoint connectivity
test_endpoint_connectivity() {
    print_header "TESTING ENDPOINT CONNECTIVITY"
    
    if ! command_exists curl; then
        log_warning "curl not available - skipping endpoint connectivity tests"
        return 0
    fi
    
    # Test endpoints
    local endpoints=(
        "Internet Endpoint:$INTERNET_ENDPOINT"
        "VPN Endpoint:$VPN_ENDPOINT"
        "Internet Models:$INTERNET_MODELS_ENDPOINT"
        "VPN Models:$VPN_MODELS_ENDPOINT"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        local name="${endpoint_info%%:*}"
        local url="${endpoint_info#*:}"
        
        if [[ -n "$url" && "$url" != "null" ]]; then
            log_info "Testing $name: $url"
            
            # Prepare curl command
            local curl_cmd="curl -s -w %{http_code} -o /tmp/endpoint_test.json"
            
            # Add API key if available
            if [[ -n "$API_KEY" && "$API_KEY" != "null" ]]; then
                curl_cmd="$curl_cmd -H 'X-API-Key: $API_KEY'"
            fi
            
            # Add URL
            curl_cmd="$curl_cmd '$url'"
            
            # Execute test
            local response_code
            response_code=$(eval "$curl_cmd" 2>/dev/null || echo "000")
            
            if [[ "$response_code" == "200" ]]; then
                log_success "$name test successful (HTTP $response_code)"
                
                # Show response if available
                if [[ -f /tmp/endpoint_test.json ]] && command_exists jq; then
                    local message
                    message=$(cat /tmp/endpoint_test.json | jq -r '.message // .status // "Response received"' 2>/dev/null || echo "Response received")
                    log_info "  Response: $message"
                fi
            elif [[ "$response_code" == "403" ]]; then
                log_warning "$name test failed (HTTP $response_code) - Check API key"
            else
                log_warning "$name test failed (HTTP $response_code)"
            fi
            
            rm -f /tmp/endpoint_test.json
        else
            log_warning "$name URL not available"
        fi
    done
}

# Function to test routing functionality
test_routing_functionality() {
    print_header "TESTING ROUTING FUNCTIONALITY"
    
    if ! command_exists curl; then
        log_warning "curl not available - skipping routing functionality tests"
        return 0
    fi
    
    # Test POST requests to both routing methods
    local test_payload='{
        "modelId": "anthropic.claude-3-haiku-20240307-v1:0",
        "body": {
            "messages": [
                {
                    "role": "user",
                    "content": "This is a test message for routing validation. Please respond with a simple confirmation."
                }
            ],
            "max_tokens": 50
        }
    }'
    
    # Test Internet routing
    if [[ -n "$INTERNET_ENDPOINT" && "$INTERNET_ENDPOINT" != "null" ]]; then
        log_info "Testing Internet routing with POST request..."
        
        local curl_cmd="curl -s -w %{http_code} -o /tmp/internet_routing_test.json -X POST -H 'Content-Type: application/json'"
        
        if [[ -n "$API_KEY" && "$API_KEY" != "null" ]]; then
            curl_cmd="$curl_cmd -H 'X-API-Key: $API_KEY'"
        fi
        
        curl_cmd="$curl_cmd -d '$test_payload' '$INTERNET_ENDPOINT'"
        
        local response_code
        response_code=$(eval "$curl_cmd" 2>/dev/null || echo "000")
        
        if [[ "$response_code" == "200" ]]; then
            log_success "Internet routing POST test successful (HTTP $response_code)"
            
            if [[ -f /tmp/internet_routing_test.json ]] && command_exists jq; then
                local routing_method
                routing_method=$(cat /tmp/internet_routing_test.json | jq -r '.routing_method // "unknown"' 2>/dev/null)
                log_info "  Routing method: $routing_method"
            fi
        else
            log_warning "Internet routing POST test failed (HTTP $response_code)"
        fi
        
        rm -f /tmp/internet_routing_test.json
    fi
    
    # Test VPN routing
    if [[ -n "$VPN_ENDPOINT" && "$VPN_ENDPOINT" != "null" ]]; then
        log_info "Testing VPN routing with POST request..."
        
        local curl_cmd="curl -s -w %{http_code} -o /tmp/vpn_routing_test.json -X POST -H 'Content-Type: application/json'"
        
        if [[ -n "$API_KEY" && "$API_KEY" != "null" ]]; then
            curl_cmd="$curl_cmd -H 'X-API-Key: $API_KEY'"
        fi
        
        curl_cmd="$curl_cmd -d '$test_payload' '$VPN_ENDPOINT'"
        
        local response_code
        response_code=$(eval "$curl_cmd" 2>/dev/null || echo "000")
        
        if [[ "$response_code" == "200" ]]; then
            log_success "VPN routing POST test successful (HTTP $response_code)"
            
            if [[ -f /tmp/vpn_routing_test.json ]] && command_exists jq; then
                local routing_method
                routing_method=$(cat /tmp/vpn_routing_test.json | jq -r '.routing_method // "unknown"' 2>/dev/null)
                log_info "  Routing method: $routing_method"
            fi
        else
            log_warning "VPN routing POST test failed (HTTP $response_code)"
        fi
        
        rm -f /tmp/vpn_routing_test.json
    fi
}

# Function to run load testing
run_load_testing() {
    if [[ "$LOAD_TEST" != "true" ]]; then
        return 0
    fi
    
    print_header "RUNNING LOAD TESTING"
    
    if ! command_exists curl; then
        log_warning "curl not available - skipping load testing"
        return 0
    fi
    
    log_info "Running load tests for API Gateway endpoints..."
    
    local test_count=10
    local concurrent_requests=3
    
    # Test Internet endpoint
    if [[ -n "$INTERNET_ENDPOINT" && "$INTERNET_ENDPOINT" != "null" ]]; then
        log_info "Load testing Internet endpoint ($test_count requests)..."
        
        local success_count=0
        local total_time=0
        
        for i in $(seq 1 $test_count); do
            local start_time=$(date +%s%3N)
            
            local curl_cmd="curl -s -w %{http_code} -o /dev/null"
            if [[ -n "$API_KEY" && "$API_KEY" != "null" ]]; then
                curl_cmd="$curl_cmd -H 'X-API-Key: $API_KEY'"
            fi
            curl_cmd="$curl_cmd '$INTERNET_ENDPOINT'"
            
            local response_code
            response_code=$(eval "$curl_cmd" 2>/dev/null || echo "000")
            
            local end_time=$(date +%s%3N)
            local request_time=$((end_time - start_time))
            total_time=$((total_time + request_time))
            
            if [[ "$response_code" == "200" ]]; then
                success_count=$((success_count + 1))
            fi
            
            echo -n "."
        done
        
        echo ""
        local avg_time=$((total_time / test_count))
        log_info "Internet endpoint load test results:"
        log_info "  Successful requests: $success_count/$test_count"
        log_info "  Average response time: ${avg_time}ms"
    fi
    
    # Test VPN endpoint
    if [[ -n "$VPN_ENDPOINT" && "$VPN_ENDPOINT" != "null" ]]; then
        log_info "Load testing VPN endpoint ($test_count requests)..."
        
        local success_count=0
        local total_time=0
        
        for i in $(seq 1 $test_count); do
            local start_time=$(date +%s%3N)
            
            local curl_cmd="curl -s -w %{http_code} -o /dev/null"
            if [[ -n "$API_KEY" && "$API_KEY" != "null" ]]; then
                curl_cmd="$curl_cmd -H 'X-API-Key: $API_KEY'"
            fi
            curl_cmd="$curl_cmd '$VPN_ENDPOINT'"
            
            local response_code
            response_code=$(eval "$curl_cmd" 2>/dev/null || echo "000")
            
            local end_time=$(date +%s%3N)
            local request_time=$((end_time - start_time))
            total_time=$((total_time + request_time))
            
            if [[ "$response_code" == "200" ]]; then
                success_count=$((success_count + 1))
            fi
            
            echo -n "."
        done
        
        echo ""
        local avg_time=$((total_time / test_count))
        log_info "VPN endpoint load test results:"
        log_info "  Successful requests: $success_count/$test_count"
        log_info "  Average response time: ${avg_time}ms"
    fi
}

# Function to generate test report
generate_test_report() {
    print_header "GENERATING TEST REPORT"
    
    local report_file="$PROJECT_ROOT/outputs/api-gateway-test-report-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "API Gateway Dual Routing Test Report"
        echo "Generated: $(date)"
        echo "Project: $PROJECT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo ""
        echo "Test Configuration:"
        echo "- API Gateway ID: ${API_GATEWAY_ID:-not provided}"
        echo "- Stack Name: ${STACK_NAME:-not provided}"
        echo "- AWS Region: ${AWS_REGION:-us-gov-west-1}"
        echo "- API Key Used: ${API_KEY:+yes}"
        echo ""
        echo "Endpoints Tested:"
        echo "- Internet Endpoint: ${INTERNET_ENDPOINT:-not available}"
        echo "- VPN Endpoint: ${VPN_ENDPOINT:-not available}"
        echo "- Internet Models: ${INTERNET_MODELS_ENDPOINT:-not available}"
        echo "- VPN Models: ${VPN_MODELS_ENDPOINT:-not available}"
        echo ""
        echo "Test Categories:"
        echo "- API Gateway configuration validation"
        echo "- Resource structure verification"
        echo "- Endpoint connectivity testing"
        echo "- Routing functionality validation"
        if [[ "$COMPREHENSIVE" == "true" ]]; then
            echo "- Comprehensive error handling tests"
        fi
        if [[ "$LOAD_TEST" == "true" ]]; then
            echo "- Load testing and performance validation"
        fi
        echo ""
        echo "Next Steps:"
        echo "1. Review any warnings or failures above"
        echo "2. Test with actual client applications"
        echo "3. Monitor API Gateway metrics and logs"
        echo "4. Set up additional monitoring and alerting"
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
            -s|--stack-name)
                STACK_NAME="$2"
                shift 2
                ;;
            -a|--api-gateway-id)
                API_GATEWAY_ID="$2"
                shift 2
                ;;
            -k|--api-key)
                API_KEY="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            --aws-profile)
                AWS_PROFILE="$2"
                shift 2
                ;;
            --comprehensive)
                COMPREHENSIVE="true"
                shift
                ;;
            --load-test)
                LOAD_TEST="true"
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
    AWS_REGION="${AWS_REGION:-us-gov-west-1}"
    STACK_NAME="${STACK_NAME:-$PROJECT_NAME-$ENVIRONMENT-api-gateway}"
    
    print_header "API GATEWAY DUAL ROUTING TESTING"
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "AWS Region: $AWS_REGION"
    
    # Execute test steps
    validate_prerequisites
    
    # Get API Gateway details from stack if not provided
    if [[ -z "$API_GATEWAY_ID" && -n "$STACK_NAME" ]]; then
        get_api_gateway_from_stack "$STACK_NAME"
    fi
    
    test_api_gateway_configuration
    test_endpoint_connectivity
    test_routing_functionality
    run_load_testing
    generate_test_report
    
    print_header "TESTING COMPLETED"
    log_success "API Gateway dual routing testing completed"
    log_info "Review the test report for detailed results"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi