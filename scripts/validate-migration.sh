#!/bin/bash

# Migration Validation Script
# This script validates the migration from internet to VPN routing

set -e

# Configuration
PROJECT_NAME="cross-partition-inference"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"
VALIDATION_TYPE="full"  # full, quick, performance, security

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --type TYPE              Validation type (full|quick|performance|security, default: full)"
    echo "  --project-name NAME      Project name (default: cross-partition-inference)"
    echo "  --environment ENV        Environment (default: prod)"
    echo "  --govcloud-profile PROF  AWS CLI profile for GovCloud (default: govcloud)"
    echo "  --commercial-profile PROF AWS CLI profile for Commercial (default: commercial)"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Validation Types:"
    echo "  full         Complete validation including all tests"
    echo "  quick        Basic functionality validation"
    echo "  performance  Performance and latency validation"
    echo "  security     Security and compliance validation"
    echo ""
    echo "Examples:"
    echo "  $0                       # Full validation"
    echo "  $0 --type quick          # Quick validation"
    echo "  $0 --type performance    # Performance validation only"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --type)
            VALIDATION_TYPE="$2"
            shift 2
            ;;
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
        --commercial-profile)
            COMMERCIAL_PROFILE="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🔍 Migration Validation${NC}"
echo -e "${BLUE}Type: ${VALIDATION_TYPE}${NC}"
echo -e "${BLUE}Project: ${PROJECT_NAME}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo ""

# Validation results
VALIDATION_RESULTS=()
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Function to add validation result
add_validation_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    local details="$4"
    
    VALIDATION_RESULTS+=("$test_name:$status:$message:$details")
    
    case "$status" in
        "PASS")
            echo -e "${GREEN}✅ $test_name: $message${NC}"
            ;;
        "FAIL")
            echo -e "${RED}❌ $test_name: $message${NC}"
            ((VALIDATION_ERRORS++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️ $test_name: $message${NC}"
            ((VALIDATION_WARNINGS++))
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️ $test_name: $message${NC}"
            ;;
    esac
    
    if [ -n "$details" ]; then
        echo "   Details: $details"
    fi
}

# Function to validate Lambda configuration
validate_lambda_configuration() {
    echo -e "${YELLOW}🔧 Validating Lambda Configuration${NC}"
    
    # Check Lambda function exists
    local lambda_config
    lambda_config=$(aws lambda get-function-configuration \
        --function-name "${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json 2>/dev/null || echo "{}")
    
    if [ "$lambda_config" = "{}" ]; then
        add_validation_result "lambda_exists" "FAIL" "Lambda function not found" ""
        return
    fi
    
    add_validation_result "lambda_exists" "PASS" "Lambda function found" ""
    
    # Check routing method
    local routing_method
    routing_method=$(echo "$lambda_config" | jq -r '.Environment.Variables.ROUTING_METHOD // "unknown"')
    
    if [ "$routing_method" = "vpn" ]; then
        add_validation_result "routing_method" "PASS" "Using VPN routing" ""
    elif [ "$routing_method" = "internet" ]; then
        add_validation_result "routing_method" "WARN" "Still using internet routing" "Migration may not be complete"
    else
        add_validation_result "routing_method" "FAIL" "Unknown routing method" "ROUTING_METHOD=$routing_method"
    fi
    
    # Check VPC configuration
    local vpc_id
    vpc_id=$(echo "$lambda_config" | jq -r '.VpcConfig.VpcId // "none"')
    
    if [ "$vpc_id" != "none" ] && [ "$vpc_id" != "null" ]; then
        add_validation_result "lambda_vpc" "PASS" "Lambda deployed in VPC" "VPC ID: $vpc_id"
    else
        add_validation_result "lambda_vpc" "FAIL" "Lambda not deployed in VPC" "Required for VPN routing"
    fi
    
    # Check environment variables
    local required_vars=("VPC_ENDPOINT_SECRETS" "COMMERCIAL_BEDROCK_ENDPOINT" "REQUEST_LOG_TABLE")
    for var in "${required_vars[@]}"; do
        local var_value
        var_value=$(echo "$lambda_config" | jq -r ".Environment.Variables.$var // \"missing\"")
        
        if [ "$var_value" != "missing" ] && [ "$var_value" != "null" ]; then
            add_validation_result "env_var_$var" "PASS" "$var configured" ""
        else
            add_validation_result "env_var_$var" "FAIL" "$var not configured" "Required for VPN routing"
        fi
    done
}

# Function to validate VPN infrastructure
validate_vpn_infrastructure() {
    echo -e "${YELLOW}🔗 Validating VPN Infrastructure${NC}"
    
    # Check GovCloud VPN connections
    local govcloud_vpn
    govcloud_vpn=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=$PROJECT_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json 2>/dev/null || echo '{"VpnConnections":[]}')
    
    local govcloud_vpn_count
    govcloud_vpn_count=$(echo "$govcloud_vpn" | jq '.VpnConnections | length')
    
    if [ "$govcloud_vpn_count" -gt 0 ]; then
        add_validation_result "govcloud_vpn_exists" "PASS" "GovCloud VPN connections found" "Count: $govcloud_vpn_count"
        
        # Check tunnel status
        local up_tunnels
        up_tunnels=$(echo "$govcloud_vpn" | jq '[.VpnConnections[].VgwTelemetry[] | select(.Status == "UP")] | length')
        
        if [ "$up_tunnels" -gt 0 ]; then
            add_validation_result "govcloud_vpn_tunnels" "PASS" "VPN tunnels are UP" "UP tunnels: $up_tunnels"
        else
            add_validation_result "govcloud_vpn_tunnels" "FAIL" "No VPN tunnels are UP" "Check VPN configuration"
        fi
    else
        add_validation_result "govcloud_vpn_exists" "FAIL" "No GovCloud VPN connections found" ""
    fi
    
    # Check Commercial VPN connections
    local commercial_vpn
    commercial_vpn=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=$PROJECT_NAME" \
        --profile "$COMMERCIAL_PROFILE" \
        --region us-east-1 \
        --output json 2>/dev/null || echo '{"VpnConnections":[]}')
    
    local commercial_vpn_count
    commercial_vpn_count=$(echo "$commercial_vpn" | jq '.VpnConnections | length')
    
    if [ "$commercial_vpn_count" -gt 0 ]; then
        add_validation_result "commercial_vpn_exists" "PASS" "Commercial VPN connections found" "Count: $commercial_vpn_count"
        
        # Check tunnel status
        local up_tunnels
        up_tunnels=$(echo "$commercial_vpn" | jq '[.VpnConnections[].VgwTelemetry[] | select(.Status == "UP")] | length')
        
        if [ "$up_tunnels" -gt 0 ]; then
            add_validation_result "commercial_vpn_tunnels" "PASS" "VPN tunnels are UP" "UP tunnels: $up_tunnels"
        else
            add_validation_result "commercial_vpn_tunnels" "FAIL" "No VPN tunnels are UP" "Check VPN configuration"
        fi
    else
        add_validation_result "commercial_vpn_exists" "FAIL" "No Commercial VPN connections found" ""
    fi
}

# Function to validate VPC endpoints
validate_vpc_endpoints() {
    echo -e "${YELLOW}🔌 Validating VPC Endpoints${NC}"
    
    # Check GovCloud VPC endpoints
    local govcloud_endpoints
    govcloud_endpoints=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=tag:Project,Values=$PROJECT_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json 2>/dev/null || echo '{"VpcEndpoints":[]}')
    
    local endpoint_count
    endpoint_count=$(echo "$govcloud_endpoints" | jq '.VpcEndpoints | length')
    
    if [ "$endpoint_count" -gt 0 ]; then
        add_validation_result "govcloud_vpc_endpoints" "PASS" "GovCloud VPC endpoints found" "Count: $endpoint_count"
        
        # Check endpoint states
        local available_endpoints
        available_endpoints=$(echo "$govcloud_endpoints" | jq '[.VpcEndpoints[] | select(.State == "available")] | length')
        
        if [ "$available_endpoints" -eq "$endpoint_count" ]; then
            add_validation_result "govcloud_endpoint_status" "PASS" "All VPC endpoints available" ""
        else
            add_validation_result "govcloud_endpoint_status" "WARN" "Some VPC endpoints not available" "Available: $available_endpoints/$endpoint_count"
        fi
    else
        add_validation_result "govcloud_vpc_endpoints" "FAIL" "No GovCloud VPC endpoints found" ""
    fi
    
    # Check Commercial VPC endpoints
    local commercial_endpoints
    commercial_endpoints=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=tag:Project,Values=$PROJECT_NAME" \
        --profile "$COMMERCIAL_PROFILE" \
        --region us-east-1 \
        --output json 2>/dev/null || echo '{"VpcEndpoints":[]}')
    
    local commercial_endpoint_count
    commercial_endpoint_count=$(echo "$commercial_endpoints" | jq '.VpcEndpoints | length')
    
    if [ "$commercial_endpoint_count" -gt 0 ]; then
        add_validation_result "commercial_vpc_endpoints" "PASS" "Commercial VPC endpoints found" "Count: $commercial_endpoint_count"
    else
        add_validation_result "commercial_vpc_endpoints" "FAIL" "No Commercial VPC endpoints found" ""
    fi
}

# Function to validate functionality
validate_functionality() {
    echo -e "${YELLOW}🧪 Validating Functionality${NC}"
    
    # Test Lambda function
    local test_payload='{"model_id":"anthropic.claude-3-sonnet-20240229-v1:0","prompt":"Migration validation test","max_tokens":50}'
    
    aws lambda invoke \
        --function-name "${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
        --payload "$test_payload" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        validation-test-response.json >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        add_validation_result "lambda_invocation" "PASS" "Lambda function invocation successful" ""
        
        # Check response
        if [ -f "validation-test-response.json" ]; then
            local response_content
            response_content=$(cat validation-test-response.json)
            
            if echo "$response_content" | jq -e '.response' >/dev/null 2>&1; then
                add_validation_result "lambda_response" "PASS" "Valid response received" ""
                
                # Check routing method in response
                local response_routing
                response_routing=$(echo "$response_content" | jq -r '.metadata.routing_method // "unknown"')
                
                if [ "$response_routing" = "vpn" ]; then
                    add_validation_result "response_routing" "PASS" "Response indicates VPN routing" ""
                elif [ "$response_routing" = "internet" ]; then
                    add_validation_result "response_routing" "WARN" "Response indicates internet routing" "Migration may not be complete"
                else
                    add_validation_result "response_routing" "INFO" "Routing method not specified in response" ""
                fi
            else
                add_validation_result "lambda_response" "FAIL" "Invalid response format" ""
            fi
        fi
    else
        add_validation_result "lambda_invocation" "FAIL" "Lambda function invocation failed" ""
    fi
    
    # Clean up test file
    rm -f validation-test-response.json
}

# Function to validate performance
validate_performance() {
    echo -e "${YELLOW}⚡ Validating Performance${NC}"
    
    # Run performance test
    local response_times=()
    local successful_requests=0
    
    for i in {1..5}; do
        local start_time=$(date +%s%3N)
        
        aws lambda invoke \
            --function-name "${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
            --payload '{"model_id":"anthropic.claude-3-sonnet-20240229-v1:0","prompt":"Performance test '$i'","max_tokens":50}' \
            --profile "$GOVCLOUD_PROFILE" \
            --region us-gov-west-1 \
            perf-test-$i.json >/dev/null 2>&1
        
        local end_time=$(date +%s%3N)
        local response_time=$((end_time - start_time))
        
        if [ $? -eq 0 ]; then
            response_times+=($response_time)
            ((successful_requests++))
        fi
        
        rm -f perf-test-$i.json
        sleep 1
    done
    
    if [ $successful_requests -gt 0 ]; then
        # Calculate average response time
        local total_time=0
        for time in "${response_times[@]}"; do
            total_time=$((total_time + time))
        done
        local avg_time=$((total_time / successful_requests))
        
        add_validation_result "performance_test" "PASS" "Performance test completed" "Avg: ${avg_time}ms, Success: $successful_requests/5"
        
        # Performance thresholds
        if [ $avg_time -lt 5000 ]; then
            add_validation_result "performance_latency" "PASS" "Response time within acceptable range" "${avg_time}ms average"
        elif [ $avg_time -lt 10000 ]; then
            add_validation_result "performance_latency" "WARN" "Response time higher than expected" "${avg_time}ms average"
        else
            add_validation_result "performance_latency" "FAIL" "Response time too high" "${avg_time}ms average"
        fi
    else
        add_validation_result "performance_test" "FAIL" "All performance tests failed" ""
    fi
}

# Function to validate security
validate_security() {
    echo -e "${YELLOW}🔒 Validating Security${NC}"
    
    # Check VPC Flow Logs
    local flow_logs
    flow_logs=$(aws ec2 describe-flow-logs \
        --filter "Name=resource-type,Values=VPC" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json 2>/dev/null || echo '{"FlowLogs":[]}')
    
    local flow_log_count
    flow_log_count=$(echo "$flow_logs" | jq '.FlowLogs | length')
    
    if [ "$flow_log_count" -gt 0 ]; then
        add_validation_result "vpc_flow_logs" "PASS" "VPC Flow Logs configured" "Count: $flow_log_count"
    else
        add_validation_result "vpc_flow_logs" "WARN" "No VPC Flow Logs found" "Consider enabling for security monitoring"
    fi
    
    # Check CloudTrail
    local cloudtrail
    cloudtrail=$(aws cloudtrail describe-trails \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json 2>/dev/null || echo '{"trailList":[]}')
    
    local trail_count
    trail_count=$(echo "$cloudtrail" | jq '.trailList | length')
    
    if [ "$trail_count" -gt 0 ]; then
        add_validation_result "cloudtrail" "PASS" "CloudTrail configured" "Count: $trail_count"
    else
        add_validation_result "cloudtrail" "WARN" "No CloudTrail found" "Consider enabling for audit logging"
    fi
    
    # Check encryption
    local lambda_config
    lambda_config=$(aws lambda get-function-configuration \
        --function-name "${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json 2>/dev/null || echo "{}")
    
    local kms_key
    kms_key=$(echo "$lambda_config" | jq -r '.KMSKeyArn // "none"')
    
    if [ "$kms_key" != "none" ] && [ "$kms_key" != "null" ]; then
        add_validation_result "lambda_encryption" "PASS" "Lambda function encrypted" "KMS Key configured"
    else
        add_validation_result "lambda_encryption" "INFO" "Lambda function using default encryption" ""
    fi
}

# Function to generate validation report
generate_validation_report() {
    echo -e "${BLUE}📊 Generating Validation Report${NC}"
    
    local report_file="migration-validation-report-${PROJECT_NAME}-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).json"
    
    # Convert results to JSON
    local results_json="["
    local first=true
    
    for result in "${VALIDATION_RESULTS[@]}"; do
        IFS=':' read -r test_name status message details <<< "$result"
        
        if [ "$first" = false ]; then
            results_json+=","
        fi
        first=false
        
        results_json+="{\"test\":\"$test_name\",\"status\":\"$status\",\"message\":\"$message\",\"details\":\"$details\"}"
    done
    
    results_json+="]"
    
    # Create report
    local report_data="{
        \"validation_info\": {
            \"project_name\": \"$PROJECT_NAME\",
            \"environment\": \"$ENVIRONMENT\",
            \"validation_type\": \"$VALIDATION_TYPE\",
            \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
            \"total_tests\": ${#VALIDATION_RESULTS[@]},
            \"errors\": $VALIDATION_ERRORS,
            \"warnings\": $VALIDATION_WARNINGS
        },
        \"results\": $results_json
    }"
    
    echo "$report_data" | jq '.' > "$report_file"
    
    echo -e "${GREEN}✅ Validation report generated: $report_file${NC}"
}

# Function to display validation summary
display_validation_summary() {
    echo ""
    echo -e "${BLUE}📊 Validation Summary${NC}"
    echo "=================================="
    echo "Project: $PROJECT_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Validation Type: $VALIDATION_TYPE"
    echo "Total Tests: ${#VALIDATION_RESULTS[@]}"
    echo "Errors: $VALIDATION_ERRORS"
    echo "Warnings: $VALIDATION_WARNINGS"
    echo ""
    
    if [ $VALIDATION_ERRORS -eq 0 ]; then
        if [ $VALIDATION_WARNINGS -eq 0 ]; then
            echo -e "${GREEN}🎉 All validation tests passed!${NC}"
        else
            echo -e "${YELLOW}⚠️ Validation completed with $VALIDATION_WARNINGS warning(s)${NC}"
        fi
        echo -e "${GREEN}✅ Migration appears to be successful${NC}"
    else
        echo -e "${RED}❌ Validation failed with $VALIDATION_ERRORS error(s)${NC}"
        echo -e "${RED}Migration may have issues that need to be addressed${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}📋 Next Steps:${NC}"
    if [ $VALIDATION_ERRORS -eq 0 ]; then
        echo "1. Continue monitoring for 24-48 hours"
        echo "2. Update documentation and procedures"
        echo "3. Schedule cleanup of old components"
    else
        echo "1. Review failed tests and fix issues"
        echo "2. Consider rollback if critical issues found"
        echo "3. Re-run validation after fixes"
    fi
}

# Main validation execution
main() {
    case "$VALIDATION_TYPE" in
        "quick")
            validate_lambda_configuration
            validate_functionality
            ;;
        "performance")
            validate_lambda_configuration
            validate_functionality
            validate_performance
            ;;
        "security")
            validate_lambda_configuration
            validate_security
            ;;
        "full")
            validate_lambda_configuration
            validate_vpn_infrastructure
            validate_vpc_endpoints
            validate_functionality
            validate_performance
            validate_security
            ;;
        *)
            echo -e "${RED}❌ Unknown validation type: $VALIDATION_TYPE${NC}"
            exit 1
            ;;
    esac
    
    # Generate report and summary
    generate_validation_report
    display_validation_summary
    
    # Exit with appropriate code
    if [ $VALIDATION_ERRORS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"