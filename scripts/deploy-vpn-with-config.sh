#!/bin/bash

# Deploy VPN Solution with Automatic Configuration
# This script deploys the complete VPN infrastructure and automatically generates configuration

set -e

# Configuration
PROJECT_NAME="cross-partition-inference"
ENVIRONMENT="dev"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"
CONFIG_OUTPUT_DIR="."
SKIP_DEPLOYMENT=false
VALIDATE_ONLY=false
FORCE_REDEPLOY=false

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
        --govcloud-profile)
            GOVCLOUD_PROFILE="$2"
            shift 2
            ;;
        --commercial-profile)
            COMMERCIAL_PROFILE="$2"
            shift 2
            ;;
        --config-output-dir)
            CONFIG_OUTPUT_DIR="$2"
            shift 2
            ;;
        --skip-deployment)
            SKIP_DEPLOYMENT=true
            shift
            ;;
        --validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        --force-redeploy)
            FORCE_REDEPLOY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --project-name NAME           Project name (default: cross-partition-inference)"
            echo "  --environment ENV             Environment (default: dev)"
            echo "  --govcloud-profile PROFILE   AWS CLI profile for GovCloud (default: govcloud)"
            echo "  --commercial-profile PROFILE AWS CLI profile for Commercial (default: commercial)"
            echo "  --config-output-dir DIR       Configuration output directory (default: .)"
            echo "  --skip-deployment             Skip deployment, only generate configuration"
            echo "  --validate-only               Only validate existing deployment and configuration"
            echo "  --force-redeploy              Force redeployment of all stacks"
            echo "  --help, -h                    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Deploy and configure with defaults"
            echo "  $0 --environment prod                 # Deploy for prod environment"
            echo "  $0 --skip-deployment                  # Only generate configuration"
            echo "  $0 --validate-only                    # Validate existing deployment"
            echo "  $0 --force-redeploy                   # Force complete redeployment"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🚀 VPN Solution Deployment with Configuration${NC}"
echo -e "${BLUE}Project: ${PROJECT_NAME}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}Configuration Output: ${CONFIG_OUTPUT_DIR}${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to check if AWS CLI profiles exist
check_aws_profile() {
    local profile=$1
    if ! aws configure list-profiles | grep -q "^${profile}$"; then
        echo -e "${RED}❌ AWS CLI profile '${profile}' not found${NC}"
        echo -e "${YELLOW}Please configure the profile using: aws configure --profile ${profile}${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ AWS CLI profile '${profile}' found${NC}"
}

# Function to check deployment prerequisites
check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking deployment prerequisites...${NC}"
    
    # Check AWS CLI profiles
    check_aws_profile "$GOVCLOUD_PROFILE"
    check_aws_profile "$COMMERCIAL_PROFILE"
    
    # Check required scripts
    local required_scripts=(
        "deploy-complete-vpn-solution.sh"
        "extract-vpn-config.sh"
        "get-vpn-status.sh"
        "vpn_config_manager.py"
    )
    
    for script in "${required_scripts[@]}"; do
        if [ -f "${SCRIPT_DIR}/${script}" ]; then
            echo -e "${GREEN}✅ Found ${script}${NC}"
        else
            echo -e "${RED}❌ Missing required script: ${script}${NC}"
            exit 1
        fi
    done
    
    # Check CloudFormation templates
    local template_dirs=(
        "../cloudformation/vpn-option"
        "../infrastructure"
    )
    
    for dir in "${template_dirs[@]}"; do
        if [ -d "${SCRIPT_DIR}/${dir}" ]; then
            echo -e "${GREEN}✅ Found template directory: ${dir}${NC}"
        else
            echo -e "${YELLOW}⚠️ Template directory not found: ${dir}${NC}"
        fi
    done
    
    echo ""
}

# Function to deploy VPN infrastructure
deploy_vpn_infrastructure() {
    echo -e "${YELLOW}🏗️ Deploying VPN infrastructure...${NC}"
    
    local deploy_args=(
        "--project-name" "$PROJECT_NAME"
        "--environment" "$ENVIRONMENT"
        "--govcloud-profile" "$GOVCLOUD_PROFILE"
        "--commercial-profile" "$COMMERCIAL_PROFILE"
    )
    
    if [ "$FORCE_REDEPLOY" = true ]; then
        deploy_args+=("--force-redeploy")
    fi
    
    # Run the complete VPN solution deployment
    if [ -f "${SCRIPT_DIR}/deploy-complete-vpn-solution.sh" ]; then
        echo -e "${BLUE}Running complete VPN solution deployment...${NC}"
        
        if "${SCRIPT_DIR}/deploy-complete-vpn-solution.sh" "${deploy_args[@]}"; then
            echo -e "${GREEN}✅ VPN infrastructure deployment completed${NC}"
        else
            echo -e "${RED}❌ VPN infrastructure deployment failed${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Complete VPN deployment script not found${NC}"
        exit 1
    fi
    
    echo ""
}

# Function to wait for deployment stabilization
wait_for_deployment_stabilization() {
    echo -e "${YELLOW}⏳ Waiting for deployment to stabilize...${NC}"
    
    local max_wait=300  # 5 minutes
    local wait_interval=30  # 30 seconds
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        echo -e "${BLUE}Checking deployment status... (${elapsed}/${max_wait}s)${NC}"
        
        # Check if VPN connections are available
        local govcloud_vpn_ready=false
        local commercial_vpn_ready=false
        
        # Check GovCloud VPN
        if aws ec2 describe-vpn-connections \
            --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=state,Values=available" \
            --profile "$GOVCLOUD_PROFILE" \
            --region "us-gov-west-1" \
            --query 'VpnConnections[0].VpnConnectionId' \
            --output text 2>/dev/null | grep -q "vpn-"; then
            govcloud_vpn_ready=true
        fi
        
        # Check Commercial VPN
        if aws ec2 describe-vpn-connections \
            --filters "Name=tag:Project,Values=${PROJECT_NAME}" "Name=state,Values=available" \
            --profile "$COMMERCIAL_PROFILE" \
            --region "us-east-1" \
            --query 'VpnConnections[0].VpnConnectionId' \
            --output text 2>/dev/null | grep -q "vpn-"; then
            commercial_vpn_ready=true
        fi
        
        if [ "$govcloud_vpn_ready" = true ] && [ "$commercial_vpn_ready" = true ]; then
            echo -e "${GREEN}✅ VPN connections are available${NC}"
            break
        fi
        
        echo -e "${YELLOW}⏳ VPN connections not yet ready, waiting...${NC}"
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    if [ $elapsed -ge $max_wait ]; then
        echo -e "${YELLOW}⚠️ Deployment stabilization timeout reached${NC}"
        echo -e "${YELLOW}Proceeding with configuration extraction...${NC}"
    fi
    
    echo ""
}

# Function to extract and generate configuration
extract_configuration() {
    echo -e "${YELLOW}🔧 Extracting VPN configuration...${NC}"
    
    local extract_args=(
        "--project-name" "$PROJECT_NAME"
        "--environment" "$ENVIRONMENT"
        "--govcloud-profile" "$GOVCLOUD_PROFILE"
        "--commercial-profile" "$COMMERCIAL_PROFILE"
        "--output-dir" "$CONFIG_OUTPUT_DIR"
    )
    
    # Run configuration extraction
    if "${SCRIPT_DIR}/extract-vpn-config.sh" "${extract_args[@]}"; then
        echo -e "${GREEN}✅ Configuration extraction completed${NC}"
    else
        echo -e "${RED}❌ Configuration extraction failed${NC}"
        exit 1
    fi
    
    echo ""
}

# Function to validate deployment and configuration
validate_deployment() {
    echo -e "${YELLOW}🔍 Validating deployment and configuration...${NC}"
    
    local validation_errors=0
    
    # Validate configuration files exist
    local config_files=(
        "${CONFIG_OUTPUT_DIR}/config-vpn.sh"
        "${CONFIG_OUTPUT_DIR}/vpn-config-data.json"
        "${CONFIG_OUTPUT_DIR}/vpn-config-validation.json"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "${GREEN}✅ Configuration file exists: $file${NC}"
        else
            echo -e "${RED}❌ Missing configuration file: $file${NC}"
            ((validation_errors++))
        fi
    done
    
    # Load and validate configuration
    if [ -f "${CONFIG_OUTPUT_DIR}/config-vpn.sh" ]; then
        echo -e "${BLUE}Loading and validating configuration...${NC}"
        
        # Source the configuration
        source "${CONFIG_OUTPUT_DIR}/config-vpn.sh"
        
        # Run validation function
        if validate_vpn_config; then
            echo -e "${GREEN}✅ Configuration validation passed${NC}"
        else
            echo -e "${RED}❌ Configuration validation failed${NC}"
            ((validation_errors++))
        fi
    fi
    
    # Test VPN connectivity
    if [ -f "${SCRIPT_DIR}/get-vpn-status.sh" ]; then
        echo -e "${BLUE}Testing VPN connectivity...${NC}"
        "${SCRIPT_DIR}/get-vpn-status.sh" test
    fi
    
    # Check validation results file
    if [ -f "${CONFIG_OUTPUT_DIR}/vpn-config-validation.json" ]; then
        local validation_status
        validation_status=$(jq -r '.is_valid' "${CONFIG_OUTPUT_DIR}/vpn-config-validation.json" 2>/dev/null || echo "false")
        
        if [ "$validation_status" = "true" ]; then
            echo -e "${GREEN}✅ Configuration validation file indicates success${NC}"
        else
            echo -e "${RED}❌ Configuration validation file indicates errors${NC}"
            
            # Show validation errors
            echo -e "${YELLOW}Validation errors:${NC}"
            jq -r '.errors[]' "${CONFIG_OUTPUT_DIR}/vpn-config-validation.json" 2>/dev/null | while read -r error; do
                echo -e "${RED}  - $error${NC}"
            done
            
            # Show validation warnings
            echo -e "${YELLOW}Validation warnings:${NC}"
            jq -r '.warnings[]' "${CONFIG_OUTPUT_DIR}/vpn-config-validation.json" 2>/dev/null | while read -r warning; do
                echo -e "${YELLOW}  - $warning${NC}"
            done
            
            ((validation_errors++))
        fi
    fi
    
    echo ""
    
    if [ $validation_errors -eq 0 ]; then
        echo -e "${GREEN}🎉 Deployment and configuration validation passed!${NC}"
        return 0
    else
        echo -e "${RED}❌ Deployment and configuration validation failed with $validation_errors error(s)${NC}"
        return 1
    fi
}

# Function to show deployment summary
show_deployment_summary() {
    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "=================================="
    echo "Project: $PROJECT_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Configuration Directory: $CONFIG_OUTPUT_DIR"
    echo ""
    
    # Show VPN status if available
    if [ -f "${SCRIPT_DIR}/get-vpn-status.sh" ]; then
        "${SCRIPT_DIR}/get-vpn-status.sh" summary
    fi
    
    # Show configuration status
    if [ -f "${CONFIG_OUTPUT_DIR}/config-vpn.sh" ]; then
        echo -e "${GREEN}✅ Configuration file generated: ${CONFIG_OUTPUT_DIR}/config-vpn.sh${NC}"
        
        # Load configuration and show status
        source "${CONFIG_OUTPUT_DIR}/config-vpn.sh"
        show_vpn_status
    fi
    
    echo ""
    echo -e "${BLUE}📋 Next Steps:${NC}"
    echo -e "${BLUE}  1. Load the configuration:${NC}"
    echo -e "${BLUE}     source ${CONFIG_OUTPUT_DIR}/config-vpn.sh${NC}"
    echo -e "${BLUE}  2. Test the Lambda function:${NC}"
    echo -e "${BLUE}     aws lambda invoke --function-name \$LAMBDA_FUNCTION_NAME response.json${NC}"
    echo -e "${BLUE}  3. Monitor VPN status:${NC}"
    echo -e "${BLUE}     ${SCRIPT_DIR}/get-vpn-status.sh watch${NC}"
    echo -e "${BLUE}  4. View monitoring dashboard:${NC}"
    echo -e "${BLUE}     echo \$MONITORING_DASHBOARD_URL${NC}"
    echo ""
}

# Function to create deployment validation report
create_deployment_report() {
    local report_file="${CONFIG_OUTPUT_DIR}/deployment-report.json"
    
    echo -e "${YELLOW}📝 Creating deployment report...${NC}"
    
    local report_data="{
        \"deployment_info\": {
            \"project_name\": \"$PROJECT_NAME\",
            \"environment\": \"$ENVIRONMENT\",
            \"deployment_timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
            \"govcloud_profile\": \"$GOVCLOUD_PROFILE\",
            \"commercial_profile\": \"$COMMERCIAL_PROFILE\",
            \"config_output_dir\": \"$CONFIG_OUTPUT_DIR\"
        },
        \"deployment_status\": \"completed\",
        \"configuration_files\": []
    }"
    
    # Add configuration files to report
    for file in "${CONFIG_OUTPUT_DIR}"/config-vpn.sh "${CONFIG_OUTPUT_DIR}"/vpn-config-data.json "${CONFIG_OUTPUT_DIR}"/vpn-config-validation.json; do
        if [ -f "$file" ]; then
            report_data=$(echo "$report_data" | jq --arg file "$(basename "$file")" '.configuration_files += [$file]')
        fi
    done
    
    # Add validation results if available
    if [ -f "${CONFIG_OUTPUT_DIR}/vpn-config-validation.json" ]; then
        local validation_data
        validation_data=$(cat "${CONFIG_OUTPUT_DIR}/vpn-config-validation.json")
        report_data=$(echo "$report_data" | jq --argjson validation "$validation_data" '.validation_results = $validation')
    fi
    
    echo "$report_data" | jq '.' > "$report_file"
    
    echo -e "${GREEN}✅ Deployment report created: $report_file${NC}"
}

# Main execution flow
main() {
    # Check prerequisites
    check_prerequisites
    
    if [ "$VALIDATE_ONLY" = true ]; then
        echo -e "${YELLOW}🔍 Validation-only mode${NC}"
        validate_deployment
        exit $?
    fi
    
    if [ "$SKIP_DEPLOYMENT" = false ]; then
        # Deploy VPN infrastructure
        deploy_vpn_infrastructure
        
        # Wait for deployment to stabilize
        wait_for_deployment_stabilization
    else
        echo -e "${YELLOW}⏭️ Skipping deployment (--skip-deployment specified)${NC}"
    fi
    
    # Extract configuration
    extract_configuration
    
    # Validate deployment and configuration
    if validate_deployment; then
        echo -e "${GREEN}🎉 VPN solution deployment and configuration completed successfully!${NC}"
        
        # Show deployment summary
        show_deployment_summary
        
        # Create deployment report
        create_deployment_report
        
        # Auto-load configuration if in current directory
        if [ "$CONFIG_OUTPUT_DIR" = "." ] && [ -f "./config-vpn.sh" ]; then
            echo -e "${YELLOW}🔄 Auto-loading configuration...${NC}"
            source "./config-vpn.sh"
            echo -e "${GREEN}✅ Configuration loaded and ready to use${NC}"
        fi
        
        exit 0
    else
        echo -e "${RED}❌ VPN solution deployment validation failed${NC}"
        echo -e "${YELLOW}Check the errors above and run validation again${NC}"
        exit 1
    fi
}

# Run main function
main "$@"