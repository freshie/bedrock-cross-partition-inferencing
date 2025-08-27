#!/bin/bash

# Validate VPN Connectivity and Configuration
# This script performs comprehensive validation of VPN connectivity and configuration

set -e

# Configuration
PROJECT_NAME="cross-partition-inference"
ENVIRONMENT="dev"
CONFIG_DIR="."
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"
VERBOSE=false
CONTINUOUS_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
        --config-dir)
            CONFIG_DIR="$2"
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
        --verbose)
            VERBOSE=true
            shift
            ;;
        --continuous)
            CONTINUOUS_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --project-name NAME           Project name (default: cross-partition-inference)"
            echo "  --environment ENV             Environment (default: dev)"
            echo "  --config-dir DIR              Configuration directory (default: .)"
            echo "  --govcloud-profile PROFILE   AWS CLI profile for GovCloud (default: govcloud)"
            echo "  --commercial-profile PROFILE AWS CLI profile for Commercial (default: commercial)"
            echo "  --verbose                     Enable verbose output"
            echo "  --continuous                  Run continuous validation (every 60 seconds)"
            echo "  --help, -h                    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                            # Validate with defaults"
            echo "  $0 --verbose                  # Verbose validation"
            echo "  $0 --continuous               # Continuous monitoring"
            echo "  $0 --config-dir ./config      # Use specific config directory"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🔍 VPN Connectivity and Configuration Validation${NC}"
echo -e "${BLUE}Project: ${PROJECT_NAME}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}Configuration Directory: ${CONFIG_DIR}${NC}"
echo ""

# Function to log verbose messages
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE] $1${NC}"
    fi
}

# Function to validate configuration files
validate_config_files() {
    echo -e "${YELLOW}📁 Validating configuration files...${NC}"
    
    local errors=0
    local config_files=(
        "${CONFIG_DIR}/config-vpn.sh"
        "${CONFIG_DIR}/vpn-config-data.json"
        "${CONFIG_DIR}/vpn-config-validation.json"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${GREEN}✅ Found: $(basename "$file")${NC}"
            log_verbose "File path: $file"
            
            # Check file permissions
            if [ -r "$file" ]; then
                log_verbose "File is readable"
            else
                echo -e "${RED}❌ File is not readable: $file${NC}"
                ((errors++))
            fi
            
            # Check file size
            local file_size
            file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            if [ "$file_size" -gt 0 ]; then
                log_verbose "File size: $file_size bytes"
            else
                echo -e "${RED}❌ File is empty: $file${NC}"
                ((errors++))
            fi
            
        else
            echo -e "${RED}❌ Missing: $(basename "$file")${NC}"
            ((errors++))
        fi
    done
    
    # Validate JSON files
    for json_file in "${CONFIG_DIR}/vpn-config-data.json" "${CONFIG_DIR}/vpn-config-validation.json"; do
        if [ -f "$json_file" ]; then
            if jq empty "$json_file" 2>/dev/null; then
                log_verbose "Valid JSON: $(basename "$json_file")"
            else
                echo -e "${RED}❌ Invalid JSON: $(basename "$json_file")${NC}"
                ((errors++))
            fi
        fi
    done
    
    # Validate shell script syntax
    if [ -f "${CONFIG_DIR}/config-vpn.sh" ]; then
        if bash -n "${CONFIG_DIR}/config-vpn.sh" 2>/dev/null; then
            log_verbose "Valid shell script: config-vpn.sh"
        else
            echo -e "${RED}❌ Invalid shell script syntax: config-vpn.sh${NC}"
            ((errors++))
        fi
    fi
    
    echo ""
    return $errors
}

# Function to validate VPN infrastructure
validate_vpn_infrastructure() {
    echo -e "${YELLOW}🏗️ Validating VPN infrastructure...${NC}"
    
    local errors=0
    
    # Check GovCloud VPN connections
    log_verbose "Checking GovCloud VPN connections..."
    local govcloud_vpn_count
    govcloud_vpn_count=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "us-gov-west-1" \
        --query 'length(VpnConnections)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$govcloud_vpn_count" -gt 0 ]; then
        echo -e "${GREEN}✅ GovCloud VPN connections found: $govcloud_vpn_count${NC}"
        
        # Check VPN connection states
        local available_count
        available_count=$(aws ec2 describe-vpn-connections \
            --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=state,Values=available" \
            --profile "$GOVCLOUD_PROFILE" \
            --region "us-gov-west-1" \
            --query 'length(VpnConnections)' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$available_count" -eq "$govcloud_vpn_count" ]; then
            echo -e "${GREEN}✅ All GovCloud VPN connections are available${NC}"
        else
            echo -e "${YELLOW}⚠️ Some GovCloud VPN connections are not available ($available_count/$govcloud_vpn_count)${NC}"
        fi
    else
        echo -e "${RED}❌ No GovCloud VPN connections found${NC}"
        ((errors++))
    fi
    
    # Check Commercial VPN connections
    log_verbose "Checking Commercial VPN connections..."
    local commercial_vpn_count
    commercial_vpn_count=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "$COMMERCIAL_PROFILE" \
        --region "us-east-1" \
        --query 'length(VpnConnections)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$commercial_vpn_count" -gt 0 ]; then
        echo -e "${GREEN}✅ Commercial VPN connections found: $commercial_vpn_count${NC}"
        
        # Check VPN connection states
        local available_count
        available_count=$(aws ec2 describe-vpn-connections \
            --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=state,Values=available" \
            --profile "$COMMERCIAL_PROFILE" \
            --region "us-east-1" \
            --query 'length(VpnConnections)' \
            --output text 2>/dev/null || echo "0")
        
        if [ "$available_count" -eq "$commercial_vpn_count" ]; then
            echo -e "${GREEN}✅ All Commercial VPN connections are available${NC}"
        else
            echo -e "${YELLOW}⚠️ Some Commercial VPN connections are not available ($available_count/$commercial_vpn_count)${NC}"
        fi
    else
        echo -e "${RED}❌ No Commercial VPN connections found${NC}"
        ((errors++))
    fi
    
    echo ""
    return $errors
}

# Function to test VPN tunnel connectivity
test_vpn_tunnels() {
    echo -e "${YELLOW}🔗 Testing VPN tunnel connectivity...${NC}"
    
    local errors=0
    
    # Get tunnel status from both partitions
    local govcloud_up_tunnels
    govcloud_up_tunnels=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "us-gov-west-1" \
        --query 'VpnConnections[*].VgwTelemetry[?Status==`UP`]' \
        --output json 2>/dev/null | jq '[.[][]] | length' || echo "0")
    
    local commercial_up_tunnels
    commercial_up_tunnels=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "$COMMERCIAL_PROFILE" \
        --region "us-east-1" \
        --query 'VpnConnections[*].VgwTelemetry[?Status==`UP`]' \
        --output json 2>/dev/null | jq '[.[][]] | length' || echo "0")
    
    echo "GovCloud UP tunnels: $govcloud_up_tunnels"
    echo "Commercial UP tunnels: $commercial_up_tunnels"
    
    if [ "$govcloud_up_tunnels" -gt 0 ] && [ "$commercial_up_tunnels" -gt 0 ]; then
        echo -e "${GREEN}✅ VPN tunnels are UP in both partitions${NC}"
        
        # Test cross-partition connectivity if possible
        if [ -f "${CONFIG_DIR}/config-vpn.sh" ]; then
            source "${CONFIG_DIR}/config-vpn.sh"
            
            # Test VPC endpoint connectivity
            if [ -n "$VPC_ENDPOINT_SECRETS" ]; then
                log_verbose "Testing Secrets Manager VPC endpoint connectivity..."
                local endpoint_host
                endpoint_host=$(echo "$VPC_ENDPOINT_SECRETS" | cut -d'.' -f1)
                
                if timeout 5 nc -z "$endpoint_host" 443 2>/dev/null; then
                    echo -e "${GREEN}✅ Secrets Manager VPC endpoint is reachable${NC}"
                else
                    echo -e "${YELLOW}⚠️ Secrets Manager VPC endpoint connectivity test failed${NC}"
                    log_verbose "This may be normal if testing from outside the VPC"
                fi
            fi
        fi
        
    elif [ "$govcloud_up_tunnels" -gt 0 ] || [ "$commercial_up_tunnels" -gt 0 ]; then
        echo -e "${YELLOW}⚠️ Partial VPN connectivity - some tunnels are down${NC}"
        ((errors++))
    else
        echo -e "${RED}❌ No VPN tunnels are UP${NC}"
        ((errors++))
    fi
    
    echo ""
    return $errors
}

# Function to validate Lambda function configuration
validate_lambda_config() {
    echo -e "${YELLOW}⚡ Validating Lambda function configuration...${NC}"
    
    local errors=0
    
    if [ -f "${CONFIG_DIR}/config-vpn.sh" ]; then
        source "${CONFIG_DIR}/config-vpn.sh"
        
        if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
            log_verbose "Checking Lambda function: $LAMBDA_FUNCTION_NAME"
            
            # Check if Lambda function exists
            if aws lambda get-function \
                --function-name "$LAMBDA_FUNCTION_NAME" \
                --profile "$GOVCLOUD_PROFILE" \
                --region "us-gov-west-1" \
                --query 'Configuration.FunctionName' \
                --output text >/dev/null 2>&1; then
                
                echo -e "${GREEN}✅ Lambda function exists: $LAMBDA_FUNCTION_NAME${NC}"
                
                # Check VPC configuration
                local vpc_config
                vpc_config=$(aws lambda get-function-configuration \
                    --function-name "$LAMBDA_FUNCTION_NAME" \
                    --profile "$GOVCLOUD_PROFILE" \
                    --region "us-gov-west-1" \
                    --query 'VpcConfig' \
                    --output json 2>/dev/null || echo "{}")
                
                if echo "$vpc_config" | jq -e '.VpcId' >/dev/null 2>&1; then
                    local lambda_vpc_id
                    lambda_vpc_id=$(echo "$vpc_config" | jq -r '.VpcId')
                    echo -e "${GREEN}✅ Lambda is configured for VPC: $lambda_vpc_id${NC}"
                    
                    # Verify it matches our expected VPC
                    if [ "$lambda_vpc_id" = "$GOVCLOUD_VPC_ID" ]; then
                        echo -e "${GREEN}✅ Lambda VPC matches configuration${NC}"
                    else
                        echo -e "${YELLOW}⚠️ Lambda VPC ($lambda_vpc_id) doesn't match expected ($GOVCLOUD_VPC_ID)${NC}"
                    fi
                else
                    echo -e "${RED}❌ Lambda function is not configured for VPC${NC}"
                    ((errors++))
                fi
                
            else
                echo -e "${RED}❌ Lambda function not found: $LAMBDA_FUNCTION_NAME${NC}"
                ((errors++))
            fi
        else
            echo -e "${YELLOW}⚠️ Lambda function name not configured${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ Configuration file not found, skipping Lambda validation${NC}"
    fi
    
    echo ""
    return $errors
}

# Function to validate VPC endpoints
validate_vpc_endpoints() {
    echo -e "${YELLOW}🔌 Validating VPC endpoints...${NC}"
    
    local errors=0
    
    if [ -f "${CONFIG_DIR}/config-vpn.sh" ]; then
        source "${CONFIG_DIR}/config-vpn.sh"
        
        # Check GovCloud VPC endpoints
        local govcloud_endpoints=(
            "VPC_ENDPOINT_SECRETS:Secrets Manager"
            "VPC_ENDPOINT_DYNAMODB:DynamoDB"
            "VPC_ENDPOINT_LOGS:CloudWatch Logs"
            "VPC_ENDPOINT_MONITORING:CloudWatch Monitoring"
        )
        
        for endpoint_info in "${govcloud_endpoints[@]}"; do
            local var_name="${endpoint_info%%:*}"
            local service_name="${endpoint_info##*:}"
            local endpoint_url="${!var_name}"
            
            if [ -n "$endpoint_url" ]; then
                echo -e "${GREEN}✅ $service_name endpoint configured${NC}"
                log_verbose "$service_name: $endpoint_url"
            else
                echo -e "${YELLOW}⚠️ $service_name endpoint not configured${NC}"
            fi
        done
        
        # Check Commercial VPC endpoints
        local commercial_endpoints=(
            "COMMERCIAL_BEDROCK_ENDPOINT:Bedrock"
            "COMMERCIAL_LOGS_ENDPOINT:CloudWatch Logs"
            "COMMERCIAL_MONITORING_ENDPOINT:CloudWatch Monitoring"
        )
        
        for endpoint_info in "${commercial_endpoints[@]}"; do
            local var_name="${endpoint_info%%:*}"
            local service_name="${endpoint_info##*:}"
            local endpoint_url="${!var_name}"
            
            if [ -n "$endpoint_url" ]; then
                echo -e "${GREEN}✅ Commercial $service_name endpoint configured${NC}"
                log_verbose "Commercial $service_name: $endpoint_url"
            else
                echo -e "${YELLOW}⚠️ Commercial $service_name endpoint not configured${NC}"
            fi
        done
        
    else
        echo -e "${YELLOW}⚠️ Configuration file not found, skipping VPC endpoint validation${NC}"
    fi
    
    echo ""
    return $errors
}

# Function to run comprehensive validation
run_comprehensive_validation() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${BLUE}🔍 Comprehensive Validation - $timestamp${NC}"
    echo "=================================================================="
    
    local total_errors=0
    
    # Validate configuration files
    validate_config_files
    total_errors=$((total_errors + $?))
    
    # Validate VPN infrastructure
    validate_vpn_infrastructure
    total_errors=$((total_errors + $?))
    
    # Test VPN tunnels
    test_vpn_tunnels
    total_errors=$((total_errors + $?))
    
    # Validate Lambda configuration
    validate_lambda_config
    total_errors=$((total_errors + $?))
    
    # Validate VPC endpoints
    validate_vpc_endpoints
    total_errors=$((total_errors + $?))
    
    # Summary
    echo -e "${BLUE}📊 Validation Summary${NC}"
    echo "=================================================================="
    
    if [ $total_errors -eq 0 ]; then
        echo -e "${GREEN}🎉 All validation checks passed!${NC}"
        echo -e "${GREEN}✅ VPN connectivity solution is properly configured and operational${NC}"
        
        # Show quick status
        if [ -f "${CONFIG_DIR}/config-vpn.sh" ]; then
            source "${CONFIG_DIR}/config-vpn.sh"
            echo ""
            echo -e "${BLUE}Quick Status:${NC}"
            echo "  Project: $PROJECT_NAME"
            echo "  Environment: $ENVIRONMENT"
            echo "  GovCloud VPC: $GOVCLOUD_VPC_ID"
            echo "  Commercial VPC: $COMMERCIAL_VPC_ID"
            echo "  Lambda Function: $LAMBDA_FUNCTION_NAME"
        fi
        
        return 0
    else
        echo -e "${RED}❌ Validation failed with $total_errors error(s)${NC}"
        echo -e "${YELLOW}Please review the errors above and fix the issues${NC}"
        return 1
    fi
}

# Function for continuous monitoring
run_continuous_monitoring() {
    echo -e "${BLUE}👀 Starting continuous VPN validation monitoring${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""
    
    local iteration=1
    
    while true; do
        clear
        echo -e "${BLUE}🔄 Continuous VPN Validation - Iteration $iteration${NC}"
        echo ""
        
        run_comprehensive_validation
        
        echo ""
        echo -e "${BLUE}Next validation in 60 seconds... (Iteration $((iteration + 1)))${NC}"
        
        sleep 60
        ((iteration++))
    done
}

# Main execution
if [ "$CONTINUOUS_MODE" = true ]; then
    run_continuous_monitoring
else
    run_comprehensive_validation
    exit $?
fi