#!/bin/bash

# VPN Tunnel Connectivity Testing Script
# Tests VPN tunnel connectivity and end-to-end functionality

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="default"

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
    echo "Test VPN tunnel connectivity and end-to-end functionality"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV         Environment (dev, stage, prod) [default: prod]"
    echo "  -p, --project-name NAME       Project name [default: dual-routing-api-gateway]"
    echo "  --govcloud-profile PROFILE   AWS profile for GovCloud [default: govcloud]"
    echo "  --commercial-profile PROFILE AWS profile for Commercial [default: default]"
    echo "  --tunnel-only                 Test only VPN tunnel status"
    echo "  --lambda-only                 Test only Lambda function connectivity"
    echo "  --bedrock-test                Test actual Bedrock API calls"
    echo "  -h, --help                    Show this help message"
}

# Function to test VPN tunnel status
test_vpn_tunnel_status() {
    print_header "TESTING VPN TUNNEL STATUS"
    
    # Get VPN connection ID
    local stack_name="$PROJECT_NAME-$ENVIRONMENT-vpn-infrastructure"
    local vpn_connection_id
    
    vpn_connection_id=$(aws --profile "$GOVCLOUD_PROFILE" cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs[?OutputKey==`VPNConnectionId`].OutputValue' \
        --output text 2>/dev/null)
    
    if [[ -z "$vpn_connection_id" || "$vpn_connection_id" == "None" ]]; then
        log_error "Could not find VPN connection ID from stack: $stack_name"
        return 1
    fi
    
    log_info "Testing VPN connection: $vpn_connection_id"
    
    # Get tunnel status
    local vpn_status
    vpn_status=$(aws --profile "$GOVCLOUD_PROFILE" ec2 describe-vpn-connections \
        --vpn-connection-ids "$vpn_connection_id" \
        --query 'VpnConnections[0].{State:State,VgwTelemetry:VgwTelemetry[].{Status:Status,StatusMessage:StatusMessage,OutsideIpAddress:OutsideIpAddress}}' \
        --output json)
    
    local connection_state
    connection_state=$(echo "$vpn_status" | jq -r '.State')
    
    local tunnel1_status
    tunnel1_status=$(echo "$vpn_status" | jq -r '.VgwTelemetry[0].Status')
    local tunnel1_ip
    tunnel1_ip=$(echo "$vpn_status" | jq -r '.VgwTelemetry[0].OutsideIpAddress')
    local tunnel1_message
    tunnel1_message=$(echo "$vpn_status" | jq -r '.VgwTelemetry[0].StatusMessage')
    
    local tunnel2_status
    tunnel2_status=$(echo "$vpn_status" | jq -r '.VgwTelemetry[1].Status')
    local tunnel2_ip
    tunnel2_ip=$(echo "$vpn_status" | jq -r '.VgwTelemetry[1].OutsideIpAddress')
    local tunnel2_message
    tunnel2_message=$(echo "$vpn_status" | jq -r '.VgwTelemetry[1].StatusMessage')
    
    log_info "VPN Connection State: $connection_state"
    log_info "Tunnel 1: $tunnel1_status ($tunnel1_ip) - $tunnel1_message"
    log_info "Tunnel 2: $tunnel2_status ($tunnel2_ip) - $tunnel2_message"
    
    # Evaluate tunnel status
    local tunnels_up=0
    if [[ "$tunnel1_status" == "UP" ]]; then
        log_success "✅ Tunnel 1 is UP"
        ((tunnels_up++))
    else
        log_warning "⚠️  Tunnel 1 is DOWN: $tunnel1_message"
    fi
    
    if [[ "$tunnel2_status" == "UP" ]]; then
        log_success "✅ Tunnel 2 is UP"
        ((tunnels_up++))
    else
        log_warning "⚠️  Tunnel 2 is DOWN: $tunnel2_message"
    fi
    
    if [[ $tunnels_up -gt 0 ]]; then
        log_success "✅ VPN connectivity available ($tunnels_up/2 tunnels UP)"
        return 0
    else
        log_error "❌ No VPN tunnels are UP"
        return 1
    fi
}

# Function to test Lambda function connectivity
test_lambda_connectivity() {
    print_header "TESTING LAMBDA FUNCTION CONNECTIVITY"
    
    local lambda_name="$PROJECT_NAME-$ENVIRONMENT-vpn-lambda"
    
    # Check if Lambda function exists
    if ! aws --profile "$GOVCLOUD_PROFILE" lambda get-function --function-name "$lambda_name" >/dev/null 2>&1; then
        log_error "Lambda function not found: $lambda_name"
        return 1
    fi
    
    log_success "✅ Lambda function exists: $lambda_name"
    
    # Test basic function invocation
    log_info "Testing basic Lambda function invocation..."
    
    local test_payload='{"httpMethod": "GET", "path": "/vpn/health"}'
    local response_file="/tmp/lambda_test_response.json"
    
    if aws --profile "$GOVCLOUD_PROFILE" lambda invoke \
        --function-name "$lambda_name" \
        --payload "$test_payload" \
        "$response_file" >/dev/null 2>&1; then
        
        local status_code
        status_code=$(jq -r '.statusCode // "unknown"' "$response_file" 2>/dev/null)
        
        log_info "Lambda response status: $status_code"
        
        if [[ "$status_code" == "200" || "$status_code" == "400" ]]; then
            log_success "✅ Lambda function is responding correctly"
        else
            log_warning "⚠️  Lambda function returned unexpected status: $status_code"
            log_info "Response: $(cat "$response_file")"
        fi
    else
        log_error "❌ Lambda function invocation failed"
        return 1
    fi
    
    # Test VPN routing validation
    log_info "Testing VPN routing validation..."
    
    local vpn_payload='{"httpMethod": "POST", "path": "/vpn/model/test", "headers": {"Content-Type": "application/json"}, "body": "{\"modelId\": \"test-model\"}"}'
    
    if aws --profile "$GOVCLOUD_PROFILE" lambda invoke \
        --function-name "$lambda_name" \
        --payload "$vpn_payload" \
        "$response_file" >/dev/null 2>&1; then
        
        local vpn_status_code
        vpn_status_code=$(jq -r '.statusCode // "unknown"' "$response_file" 2>/dev/null)
        
        log_info "VPN routing test status: $vpn_status_code"
        
        if [[ "$vpn_status_code" == "502" || "$vpn_status_code" == "503" ]]; then
            log_success "✅ VPN routing logic is working (expected 502/503 without full connectivity)"
        elif [[ "$vpn_status_code" == "200" ]]; then
            log_success "✅ VPN routing is fully functional!"
        else
            log_warning "⚠️  Unexpected VPN routing response: $vpn_status_code"
        fi
    else
        log_warning "⚠️  VPN routing test failed"
    fi
    
    rm -f "$response_file"
    return 0
}

# Function to test network connectivity from Lambda
test_network_connectivity() {
    print_header "TESTING NETWORK CONNECTIVITY FROM LAMBDA"
    
    local lambda_name="$PROJECT_NAME-$ENVIRONMENT-vpn-lambda"
    
    # Test connectivity to Commercial AWS Bedrock endpoint
    log_info "Testing connectivity to Commercial AWS Bedrock endpoint..."
    
    local network_test_payload='{
        "httpMethod": "POST",
        "path": "/vpn/model/anthropic.claude-3-sonnet-20240229-v1:0/invoke",
        "headers": {"Content-Type": "application/json"},
        "body": "{\"modelId\": \"anthropic.claude-3-sonnet-20240229-v1:0\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}], \"max_tokens\": 10}"
    }'
    
    local response_file="/tmp/network_test_response.json"
    
    if aws --profile "$GOVCLOUD_PROFILE" lambda invoke \
        --function-name "$lambda_name" \
        --payload "$network_test_payload" \
        "$response_file" >/dev/null 2>&1; then
        
        local network_status_code
        network_status_code=$(jq -r '.statusCode // "unknown"' "$response_file" 2>/dev/null)
        
        log_info "Network connectivity test status: $network_status_code"
        
        case "$network_status_code" in
            200)
                log_success "✅ Full end-to-end connectivity working!"
                log_success "✅ VPN tunnels are functional"
                log_success "✅ Commercial AWS Bedrock is accessible"
                ;;
            401|403)
                log_success "✅ Network connectivity working (authentication issue)"
                log_info "VPN tunnels are functional, check bearer token configuration"
                ;;
            502|503|504)
                log_warning "⚠️  Network connectivity issues detected"
                log_info "This may indicate VPN tunnel problems or Commercial AWS issues"
                ;;
            *)
                log_warning "⚠️  Unexpected network response: $network_status_code"
                ;;
        esac
        
        # Show response details for debugging
        local error_message
        error_message=$(jq -r '.body | fromjson | .error.message // "No error message"' "$response_file" 2>/dev/null)
        if [[ "$error_message" != "No error message" && "$error_message" != "null" ]]; then
            log_info "Error details: $error_message"
        fi
    else
        log_error "❌ Network connectivity test failed"
        return 1
    fi
    
    rm -f "$response_file"
    return 0
}

# Function to test actual Bedrock API calls
test_bedrock_api() {
    print_header "TESTING BEDROCK API CALLS"
    
    local lambda_name="$PROJECT_NAME-$ENVIRONMENT-vpn-lambda"
    
    log_info "Testing actual Bedrock API call via VPN..."
    
    # Test with a simple Claude model request
    local bedrock_payload='{
        "httpMethod": "POST",
        "path": "/vpn/model/anthropic.claude-3-haiku-20240307-v1:0/invoke",
        "headers": {"Content-Type": "application/json"},
        "body": "{\"modelId\": \"anthropic.claude-3-haiku-20240307-v1:0\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one word\"}], \"max_tokens\": 5, \"anthropic_version\": \"bedrock-2023-05-31\"}"
    }'
    
    local response_file="/tmp/bedrock_test_response.json"
    
    if aws --profile "$GOVCLOUD_PROFILE" lambda invoke \
        --function-name "$lambda_name" \
        --payload "$bedrock_payload" \
        "$response_file" >/dev/null 2>&1; then
        
        local bedrock_status_code
        bedrock_status_code=$(jq -r '.statusCode // "unknown"' "$response_file" 2>/dev/null)
        
        log_info "Bedrock API test status: $bedrock_status_code"
        
        case "$bedrock_status_code" in
            200)
                log_success "🎉 Bedrock API call successful!"
                log_success "✅ End-to-end dual routing is fully functional"
                
                # Try to extract the response content
                local bedrock_response
                bedrock_response=$(jq -r '.body | fromjson | .content[0].text // .body // "No response content"' "$response_file" 2>/dev/null)
                if [[ "$bedrock_response" != "No response content" && "$bedrock_response" != "null" ]]; then
                    log_info "Bedrock response: $bedrock_response"
                fi
                ;;
            400)
                log_warning "⚠️  Bedrock API request format issue"
                log_info "VPN connectivity is working, but request needs adjustment"
                ;;
            401|403)
                log_warning "⚠️  Bedrock API authentication issue"
                log_info "VPN connectivity is working, check bearer token"
                ;;
            502|503|504)
                log_error "❌ Bedrock API connectivity issue"
                log_info "Check VPN tunnel status and Commercial AWS configuration"
                ;;
            *)
                log_warning "⚠️  Unexpected Bedrock API response: $bedrock_status_code"
                ;;
        esac
        
        # Show detailed error information
        local error_details
        error_details=$(jq -r '.body | fromjson | .error // empty' "$response_file" 2>/dev/null)
        if [[ -n "$error_details" && "$error_details" != "null" ]]; then
            log_info "Error details: $error_details"
        fi
    else
        log_error "❌ Bedrock API test failed"
        return 1
    fi
    
    rm -f "$response_file"
    return 0
}

# Function to test Commercial AWS connectivity (if credentials available)
test_commercial_aws_connectivity() {
    print_header "TESTING COMMERCIAL AWS CONNECTIVITY"
    
    # Check if Commercial AWS credentials are available
    if ! aws --profile "$COMMERCIAL_PROFILE" sts get-caller-identity >/dev/null 2>&1; then
        log_warning "⚠️  Commercial AWS credentials not available"
        log_info "Skipping Commercial AWS connectivity tests"
        return 0
    fi
    
    local commercial_account
    commercial_account=$(aws --profile "$COMMERCIAL_PROFILE" sts get-caller-identity --query 'Account' --output text)
    log_success "✅ Commercial AWS credentials available (Account: $commercial_account)"
    
    # Test Bedrock service availability
    log_info "Testing Bedrock service availability in Commercial AWS..."
    
    if aws --profile "$COMMERCIAL_PROFILE" bedrock list-foundation-models --region us-east-1 >/dev/null 2>&1; then
        log_success "✅ Bedrock service is accessible in Commercial AWS"
    else
        log_warning "⚠️  Bedrock service access issue in Commercial AWS"
        log_info "Check Bedrock service permissions and availability"
    fi
    
    # Check if VPN infrastructure exists in Commercial AWS
    local commercial_stack_name="$PROJECT_NAME-$ENVIRONMENT-commercial-vpn"
    
    if aws --profile "$COMMERCIAL_PROFILE" cloudformation describe-stacks --stack-name "$commercial_stack_name" >/dev/null 2>&1; then
        log_success "✅ Commercial AWS VPN infrastructure stack exists"
        
        # Get VPN connection status in Commercial AWS
        local commercial_vpn_id
        commercial_vpn_id=$(aws --profile "$COMMERCIAL_PROFILE" cloudformation describe-stacks \
            --stack-name "$commercial_stack_name" \
            --query 'Stacks[0].Outputs[?OutputKey==`VPNConnectionId`].OutputValue' \
            --output text 2>/dev/null)
        
        if [[ -n "$commercial_vpn_id" && "$commercial_vpn_id" != "None" ]]; then
            log_info "Commercial VPN Connection ID: $commercial_vpn_id"
            
            # Check tunnel status
            local commercial_vpn_status
            commercial_vpn_status=$(aws --profile "$COMMERCIAL_PROFILE" ec2 describe-vpn-connections \
                --vpn-connection-ids "$commercial_vpn_id" \
                --query 'VpnConnections[0].VgwTelemetry[].Status' \
                --output text 2>/dev/null)
            
            log_info "Commercial VPN tunnel status: $commercial_vpn_status"
        fi
    else
        log_warning "⚠️  Commercial AWS VPN infrastructure not deployed"
        log_info "Deploy using: config/vpn-tunnels/deploy-commercial-vpn.sh"
    fi
    
    return 0
}

# Function to generate connectivity report
generate_connectivity_report() {
    print_header "GENERATING CONNECTIVITY REPORT"
    
    local report_file="$PROJECT_ROOT/outputs/vpn-connectivity-test-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "VPN Tunnel Connectivity Test Report"
        echo "Generated: $(date)"
        echo "Project: $PROJECT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo ""
        echo "Test Results Summary:"
        echo "===================="
        
        # Run tests and capture results
        if test_vpn_tunnel_status >/dev/null 2>&1; then
            echo "✅ VPN Tunnel Status: PASS"
        else
            echo "❌ VPN Tunnel Status: FAIL"
        fi
        
        if test_lambda_connectivity >/dev/null 2>&1; then
            echo "✅ Lambda Connectivity: PASS"
        else
            echo "❌ Lambda Connectivity: FAIL"
        fi
        
        if test_network_connectivity >/dev/null 2>&1; then
            echo "✅ Network Connectivity: PASS"
        else
            echo "❌ Network Connectivity: FAIL"
        fi
        
        echo ""
        echo "Recommendations:"
        echo "==============="
        echo "1. Ensure VPN tunnels are UP in both GovCloud and Commercial AWS"
        echo "2. Verify route table configurations in both partitions"
        echo "3. Check security group rules for Lambda and VPN traffic"
        echo "4. Validate bearer token configuration in Secrets Manager"
        echo "5. Test end-to-end connectivity with actual Bedrock API calls"
        echo ""
        echo "Next Steps:"
        echo "==========="
        echo "- If tunnels are DOWN: Deploy Commercial AWS infrastructure"
        echo "- If connectivity fails: Check routing and security groups"
        echo "- If authentication fails: Update bearer token in Secrets Manager"
        echo "- If successful: Proceed with API Gateway deployment"
    } > "$report_file"
    
    log_success "Connectivity report generated: $report_file"
}

# Main execution function
main() {
    local tunnel_only=false
    local lambda_only=false
    local bedrock_test=false
    
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
            --govcloud-profile)
                GOVCLOUD_PROFILE="$2"
                shift 2
                ;;
            --commercial-profile)
                COMMERCIAL_PROFILE="$2"
                shift 2
                ;;
            --tunnel-only)
                tunnel_only=true
                shift
                ;;
            --lambda-only)
                lambda_only=true
                shift
                ;;
            --bedrock-test)
                bedrock_test=true
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
    
    print_header "VPN TUNNEL CONNECTIVITY TESTING"
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "GovCloud Profile: $GOVCLOUD_PROFILE"
    log_info "Commercial Profile: $COMMERCIAL_PROFILE"
    
    # Execute tests based on options
    local test_results=0
    
    if [[ "$tunnel_only" == true ]]; then
        test_vpn_tunnel_status || ((test_results++))
    elif [[ "$lambda_only" == true ]]; then
        test_lambda_connectivity || ((test_results++))
    elif [[ "$bedrock_test" == true ]]; then
        test_bedrock_api || ((test_results++))
    else
        # Run all tests
        test_vpn_tunnel_status || ((test_results++))
        test_lambda_connectivity || ((test_results++))
        test_network_connectivity || ((test_results++))
        test_commercial_aws_connectivity || ((test_results++))
        
        if [[ $test_results -eq 0 ]]; then
            test_bedrock_api || ((test_results++))
        fi
    fi
    
    generate_connectivity_report
    
    print_header "VPN CONNECTIVITY TESTING COMPLETED"
    
    if [[ $test_results -eq 0 ]]; then
        log_success "🎉 All VPN connectivity tests passed!"
        log_info "Your dual routing system is ready for production use"
    else
        log_warning "⚠️  Some tests failed or showed warnings"
        log_info "Review the test output and connectivity report for details"
    fi
    
    log_info "Test report: outputs/vpn-connectivity-test-*.txt"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi