#!/bin/bash

# Emergency Rollback to Internet Routing
# This script provides emergency rollback procedures from VPN to internet routing

set -e

# Configuration
PROJECT_NAME="cross-partition-inference"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"
EMERGENCY_MODE=false
VALIDATE_ROLLBACK=true

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
    echo "  --project-name NAME      Project name (default: cross-partition-inference)"
    echo "  --environment ENV        Environment (default: prod)"
    echo "  --govcloud-profile PROF  AWS CLI profile for GovCloud (default: govcloud)"
    echo "  --commercial-profile PROF AWS CLI profile for Commercial (default: commercial)"
    echo "  --emergency              Emergency mode - skip validation for speed"
    echo "  --no-validation          Skip post-rollback validation"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                       # Standard rollback with validation"
    echo "  $0 --emergency           # Emergency rollback, skip validation"
    echo "  $0 --environment staging # Rollback staging environment"
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
        --commercial-profile)
            COMMERCIAL_PROFILE="$2"
            shift 2
            ;;
        --emergency)
            EMERGENCY_MODE=true
            VALIDATE_ROLLBACK=false
            shift
            ;;
        --no-validation)
            VALIDATE_ROLLBACK=false
            shift
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

echo -e "${RED}🚨 EMERGENCY ROLLBACK TO INTERNET ROUTING${NC}"
echo -e "${BLUE}Project: ${PROJECT_NAME}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}Emergency Mode: ${EMERGENCY_MODE}${NC}"
echo ""

if [ "$EMERGENCY_MODE" = true ]; then
    echo -e "${YELLOW}⚠️ EMERGENCY MODE ENABLED - SKIPPING SAFETY CHECKS${NC}"
    echo -e "${YELLOW}This will immediately switch to internet routing${NC}"
    echo ""
fi

# Function to log rollback actions
log_rollback_action() {
    local action="$1"
    local status="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    
    echo "[$timestamp] ROLLBACK: $action - $status" >> "rollback-log-${PROJECT_NAME}-${ENVIRONMENT}.log"
}

# Function to check current routing method
check_current_routing() {
    echo -e "${BLUE}🔍 Checking current routing method...${NC}"
    
    local current_config
    current_config=$(aws lambda get-function-configuration \
        --function-name "${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query 'Environment.Variables.ROUTING_METHOD' \
        --output text 2>/dev/null || echo "unknown")
    
    echo "Current routing method: $current_config"
    log_rollback_action "check_current_routing" "current_method=$current_config"
    
    if [ "$current_config" = "internet" ]; then
        echo -e "${YELLOW}⚠️ Already using internet routing${NC}"
        if [ "$EMERGENCY_MODE" = false ]; then
            read -p "Continue with rollback anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Rollback cancelled"
                exit 0
            fi
        fi
    fi
}

# Function to perform immediate rollback
perform_immediate_rollback() {
    echo -e "${RED}🔄 Performing immediate rollback to internet routing...${NC}"
    log_rollback_action "immediate_rollback" "started"
    
    # Switch Lambda function to internet routing
    echo -e "${BLUE}Switching Lambda function to internet routing...${NC}"
    aws lambda update-function-configuration \
        --function-name "${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
        --environment Variables='{
            "ROUTING_METHOD":"internet",
            "ENABLE_DUAL_ROUTING":"false"
        }' \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Lambda function switched to internet routing${NC}"
        log_rollback_action "lambda_switch" "success"
    else
        echo -e "${RED}❌ Failed to switch Lambda function${NC}"
        log_rollback_action "lambda_switch" "failed"
        exit 1
    fi
    
    # Wait for configuration to propagate
    echo -e "${BLUE}Waiting for configuration to propagate (30 seconds)...${NC}"
    sleep 30
    
    log_rollback_action "immediate_rollback" "completed"
}

# Function to validate internet routing
validate_internet_routing() {
    echo -e "${BLUE}🧪 Validating internet routing...${NC}"
    log_rollback_action "validation" "started"
    
    # Test Lambda function with internet routing
    echo -e "${BLUE}Testing Lambda function...${NC}"
    aws lambda invoke \
        --function-name "${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
        --payload '{
            "model_id": "anthropic.claude-3-sonnet-20240229-v1:0",
            "prompt": "Rollback validation test",
            "routing_method": "internet"
        }' \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        rollback-validation-response.json
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Lambda function test successful${NC}"
        log_rollback_action "lambda_test" "success"
        
        # Check response
        if [ -f "rollback-validation-response.json" ]; then
            local response_status
            response_status=$(jq -r '.statusCode // "unknown"' rollback-validation-response.json 2>/dev/null || echo "unknown")
            echo "Response status: $response_status"
            
            if [ "$response_status" = "200" ]; then
                echo -e "${GREEN}✅ Successful response received${NC}"
                log_rollback_action "response_validation" "success"
            else
                echo -e "${YELLOW}⚠️ Non-200 response received${NC}"
                log_rollback_action "response_validation" "warning"
            fi
        fi
    else
        echo -e "${RED}❌ Lambda function test failed${NC}"
        log_rollback_action "lambda_test" "failed"
    fi
    
    # Run internet routing tests if available
    if [ -f "tests/test_internet_routing.py" ]; then
        echo -e "${BLUE}Running internet routing tests...${NC}"
        python3 tests/test_internet_routing.py
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Internet routing tests passed${NC}"
            log_rollback_action "routing_tests" "success"
        else
            echo -e "${YELLOW}⚠️ Some internet routing tests failed${NC}"
            log_rollback_action "routing_tests" "partial_failure"
        fi
    fi
    
    log_rollback_action "validation" "completed"
}

# Function to check API Gateway status
check_api_gateway_status() {
    echo -e "${BLUE}🌐 Checking API Gateway status...${NC}"
    log_rollback_action "api_gateway_check" "started"
    
    # List API Gateways
    local api_gateways
    api_gateways=$(aws apigateway get-rest-apis \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query 'items[?contains(name, `'$PROJECT_NAME'`)].{id:id,name:name}' \
        --output json 2>/dev/null || echo "[]")
    
    local api_count
    api_count=$(echo "$api_gateways" | jq length)
    
    if [ "$api_count" -gt 0 ]; then
        echo -e "${GREEN}✅ Found $api_count API Gateway(s)${NC}"
        echo "$api_gateways" | jq -r '.[] | "  - \(.name) (\(.id))"'
        log_rollback_action "api_gateway_check" "found_$api_count"
    else
        echo -e "${YELLOW}⚠️ No API Gateways found for project${NC}"
        log_rollback_action "api_gateway_check" "none_found"
    fi
}

# Function to generate rollback report
generate_rollback_report() {
    echo -e "${BLUE}📊 Generating rollback report...${NC}"
    
    local report_file="rollback-report-${PROJECT_NAME}-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).json"
    
    # Get current Lambda configuration
    local lambda_config
    lambda_config=$(aws lambda get-function-configuration \
        --function-name "${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json 2>/dev/null || echo "{}")
    
    # Create report
    local report_data="{
        \"rollback_info\": {
            \"project_name\": \"$PROJECT_NAME\",
            \"environment\": \"$ENVIRONMENT\",
            \"rollback_timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
            \"emergency_mode\": $EMERGENCY_MODE,
            \"validation_performed\": $VALIDATE_ROLLBACK
        },
        \"lambda_configuration\": $lambda_config,
        \"rollback_log\": \"rollback-log-${PROJECT_NAME}-${ENVIRONMENT}.log\"
    }"
    
    echo "$report_data" | jq '.' > "$report_file"
    
    echo -e "${GREEN}✅ Rollback report generated: $report_file${NC}"
    log_rollback_action "report_generation" "completed"
}

# Function to display rollback summary
display_rollback_summary() {
    echo ""
    echo -e "${GREEN}🎉 ROLLBACK COMPLETED${NC}"
    echo "=================================="
    echo "Project: $PROJECT_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Rollback Time: $(date)"
    echo "Emergency Mode: $EMERGENCY_MODE"
    echo "Validation: $VALIDATE_ROLLBACK"
    echo ""
    
    echo -e "${BLUE}📋 Post-Rollback Actions:${NC}"
    echo "1. Monitor application for 30 minutes"
    echo "2. Check error rates and performance"
    echo "3. Notify stakeholders of rollback"
    echo "4. Investigate root cause of VPN issues"
    echo "5. Plan remediation before next migration attempt"
    echo ""
    
    echo -e "${YELLOW}⚠️ Important Notes:${NC}"
    echo "• Internet routing is now active"
    echo "• VPN infrastructure remains deployed"
    echo "• Monitor for any authentication issues"
    echo "• Review rollback logs for any warnings"
    echo ""
}

# Main rollback execution
main() {
    # Start rollback logging
    log_rollback_action "rollback_start" "initiated"
    
    # Pre-rollback checks (skip in emergency mode)
    if [ "$EMERGENCY_MODE" = false ]; then
        check_current_routing
        check_api_gateway_status
        
        # Confirmation prompt
        echo -e "${YELLOW}⚠️ This will switch from VPN routing back to internet routing${NC}"
        read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Rollback cancelled"
            log_rollback_action "rollback_cancelled" "user_cancelled"
            exit 0
        fi
    fi
    
    # Perform immediate rollback
    perform_immediate_rollback
    
    # Validation (if enabled)
    if [ "$VALIDATE_ROLLBACK" = true ]; then
        validate_internet_routing
    else
        echo -e "${YELLOW}⚠️ Skipping validation as requested${NC}"
        log_rollback_action "validation" "skipped"
    fi
    
    # Generate report
    generate_rollback_report
    
    # Display summary
    display_rollback_summary
    
    # Final logging
    log_rollback_action "rollback_complete" "success"
    
    echo -e "${GREEN}✅ Rollback completed successfully${NC}"
}

# Handle interrupts
trap 'echo -e "\n${RED}Rollback interrupted! System may be in inconsistent state.${NC}"; log_rollback_action "rollback_interrupted" "error"; exit 1' INT TERM

# Confirmation for emergency mode
if [ "$EMERGENCY_MODE" = true ]; then
    echo -e "${RED}🚨 EMERGENCY ROLLBACK - NO SAFETY CHECKS${NC}"
    echo -e "${YELLOW}This will immediately switch to internet routing without validation${NC}"
    echo -e "${YELLOW}Press Ctrl+C within 10 seconds to cancel...${NC}"
    sleep 10
fi

# Run main function
main "$@"