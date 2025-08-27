#!/bin/bash

# Complete VPN Solution Deployment Script
# This script orchestrates the deployment of the entire VPN connectivity solution

set -e

# Configuration
PROJECT_NAME="cross-partition-vpn"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Deployment phases
PHASES=(
    "vpc:VPC Infrastructure"
    "endpoints:VPC Endpoints"
    "vpn:VPN Gateway"
    "lambda:Lambda Functions"
    "security:Security Controls"
    "monitoring:Monitoring & Alerting"
)

echo -e "${GREEN}🚀 Complete VPN Solution Deployment${NC}"
echo -e "${BLUE}Project: $PROJECT_NAME${NC}"
echo -e "${BLUE}Environment: $ENVIRONMENT${NC}"
echo ""

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p, --phase PHASE     Deploy specific phase only (vpc|endpoints|vpn|lambda|security|monitoring|all)"
    echo "  -e, --env ENV         Environment (dev|staging|prod) [default: prod]"
    echo "  -r, --rollback        Rollback deployment"
    echo "  -v, --validate        Validate deployment only"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Phases:"
    for phase_info in "${PHASES[@]}"; do
        IFS=':' read -r phase desc <<< "$phase_info"
        echo "  $phase: $desc"
    done
    echo ""
}

# Parse command line arguments
DEPLOYMENT_PHASE="all"
ROLLBACK=false
VALIDATE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--phase)
            DEPLOYMENT_PHASE="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--rollback)
            ROLLBACK=true
            shift
            ;;
        -v|--validate)
            VALIDATE_ONLY=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done# F
unction to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking prerequisites${NC}"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI not found${NC}"
        exit 1
    fi
    
    # Check profiles
    if ! aws configure list-profiles | grep -q "^$GOVCLOUD_PROFILE$"; then
        echo -e "${RED}❌ AWS CLI profile '$GOVCLOUD_PROFILE' not found${NC}"
        exit 1
    fi
    
    if ! aws configure list-profiles | grep -q "^$COMMERCIAL_PROFILE$"; then
        echo -e "${RED}❌ AWS CLI profile '$COMMERCIAL_PROFILE' not found${NC}"
        exit 1
    fi
    
    # Check template files
    local template_dir="../infrastructure"
    local required_templates=(
        "vpn-govcloud-vpc.yaml"
        "vpn-commercial-vpc.yaml"
        "vpn-govcloud-endpoints.yaml"
        "vpn-commercial-endpoints.yaml"
        "vpn-gateway.yaml"
        "vpn-connectivity-validation.yaml"
        "vpn-lambda-function.yaml"
        "vpn-security-controls.yaml"
        "vpn-audit-compliance.yaml"
        "vpn-monitoring-alerting.yaml"
        "master-vpn-deployment.yaml"
    )
    
    for template in "${required_templates[@]}"; do
        if [ ! -f "$template_dir/$template" ]; then
            echo -e "${RED}❌ Template not found: $template_dir/$template${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to upload templates to S3
upload_templates() {
    local profile=$1
    local partition=$2
    
    echo -e "${YELLOW}📦 Uploading templates to S3 for $partition${NC}"
    
    local bucket_name="${PROJECT_NAME}-deployment-$(aws sts get-caller-identity --profile $profile --query Account --output text)-$(aws configure get region --profile $profile)"
    
    # Create bucket if it doesn't exist
    if ! aws s3 ls "s3://$bucket_name" --profile $profile &>/dev/null; then
        echo "Creating deployment bucket: $bucket_name"
        aws s3 mb "s3://$bucket_name" --profile $profile
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled \
            --profile $profile
    fi
    
    # Upload templates
    aws s3 sync ../infrastructure/ "s3://$bucket_name/templates/" \
        --profile $profile \
        --exclude "*" \
        --include "*.yaml" \
        --delete
    
    echo -e "${GREEN}✅ Templates uploaded to s3://$bucket_name/templates/${NC}"
    echo "$bucket_name"
}

# Function to deploy phase
deploy_phase() {
    local profile=$1
    local partition=$2
    local phase=$3
    local template=$4
    local dependencies=("${@:5}")
    
    echo -e "${PURPLE}🔧 Deploying $phase for $partition${NC}"
    
    local stack_name="${PROJECT_NAME}-${partition,,}-${phase}"
    local template_url="https://s3.amazonaws.com/$DEPLOYMENT_BUCKET/templates/$template"
    
    # Check dependencies
    for dep in "${dependencies[@]}"; do
        local dep_stack="${PROJECT_NAME}-${partition,,}-${dep}"
        if ! aws cloudformation describe-stacks --stack-name "$dep_stack" --profile $profile &>/dev/null; then
            echo -e "${RED}❌ Dependency not met: $dep_stack${NC}"
            return 1
        fi
    done
    
    # Deploy stack
    local params_file="/tmp/${stack_name}-params.json"
    generate_parameters "$phase" "$partition" > "$params_file"
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --profile $profile &>/dev/null; then
        echo "Updating existing stack: $stack_name"
        aws cloudformation deploy \
            --template-file "../infrastructure/$template" \
            --stack-name "$stack_name" \
            --parameter-overrides file://"$params_file" \
            --capabilities CAPABILITY_IAM \
            --profile $profile \
            --tags \
                Project="$PROJECT_NAME" \
                Environment="$ENVIRONMENT" \
                Partition="$partition" \
                Phase="$phase"
    else
        echo "Creating new stack: $stack_name"
        aws cloudformation deploy \
            --template-file "../infrastructure/$template" \
            --stack-name "$stack_name" \
            --parameter-overrides file://"$params_file" \
            --capabilities CAPABILITY_IAM \
            --profile $profile \
            --tags \
                Project="$PROJECT_NAME" \
                Environment="$ENVIRONMENT" \
                Partition="$partition" \
                Phase="$phase"
    fi
    
    rm -f "$params_file"
    echo -e "${GREEN}✅ $phase deployed successfully for $partition${NC}"
}

# Function to generate parameters for each phase
generate_parameters() {
    local phase=$1
    local partition=$2
    
    case $phase in
        "vpc")
            echo "Environment=$ENVIRONMENT ProjectName=$PROJECT_NAME"
            ;;
        "endpoints")
            echo "Environment=$ENVIRONMENT ProjectName=$PROJECT_NAME VPCStackName=${PROJECT_NAME}-${partition,,}-vpc"
            ;;
        "vpn")
            echo "Environment=$ENVIRONMENT ProjectName=$PROJECT_NAME GovCloudVPCStackName=${PROJECT_NAME}-govcloud-vpc CommercialVPCStackName=${PROJECT_NAME}-commercial-vpc GovCloudCustomerGatewayIP=203.0.113.1 CommercialCustomerGatewayIP=203.0.113.2 Tunnel1PreSharedKey=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32) Tunnel2PreSharedKey=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)"
            ;;
        "lambda")
            echo "Environment=$ENVIRONMENT ProjectName=$PROJECT_NAME VPCStackName=${PROJECT_NAME}-${partition,,}-vpc VPCEndpointsStackName=${PROJECT_NAME}-${partition,,}-endpoints"
            ;;
        "security")
            echo "Environment=$ENVIRONMENT ProjectName=$PROJECT_NAME VPCStackName=${PROJECT_NAME}-${partition,,}-vpc VPNGatewayStackName=${PROJECT_NAME}-${partition,,}-vpn"
            ;;
        "monitoring")
            echo "Environment=$ENVIRONMENT ProjectName=$PROJECT_NAME AlertEmail=admin@example.com"
            ;;
    esac
}

# Function to validate deployment
validate_deployment() {
    echo -e "${YELLOW}🧪 Validating deployment${NC}"
    
    local validation_results=()
    
    # Check GovCloud stacks
    echo "Checking GovCloud stacks..."
    local govcloud_stacks=(
        "${PROJECT_NAME}-govcloud-vpc"
        "${PROJECT_NAME}-govcloud-endpoints"
        "${PROJECT_NAME}-govcloud-vpn"
        "${PROJECT_NAME}-govcloud-lambda"
        "${PROJECT_NAME}-govcloud-security"
        "${PROJECT_NAME}-govcloud-monitoring"
    )
    
    for stack in "${govcloud_stacks[@]}"; do
        if aws cloudformation describe-stacks --stack-name "$stack" --profile $GOVCLOUD_PROFILE &>/dev/null; then
            local status=$(aws cloudformation describe-stacks --stack-name "$stack" --profile $GOVCLOUD_PROFILE --query 'Stacks[0].StackStatus' --output text)
            if [[ "$status" == "CREATE_COMPLETE" || "$status" == "UPDATE_COMPLETE" ]]; then
                validation_results+=("✅ $stack: $status")
            else
                validation_results+=("❌ $stack: $status")
            fi
        else
            validation_results+=("❌ $stack: NOT_FOUND")
        fi
    done
    
    # Check Commercial stacks
    echo "Checking Commercial stacks..."
    local commercial_stacks=(
        "${PROJECT_NAME}-commercial-vpc"
        "${PROJECT_NAME}-commercial-endpoints"
        "${PROJECT_NAME}-commercial-vpn"
        "${PROJECT_NAME}-commercial-monitoring"
    )
    
    for stack in "${commercial_stacks[@]}"; do
        if aws cloudformation describe-stacks --stack-name "$stack" --profile $COMMERCIAL_PROFILE &>/dev/null; then
            local status=$(aws cloudformation describe-stacks --stack-name "$stack" --profile $COMMERCIAL_PROFILE --query 'Stacks[0].StackStatus' --output text)
            if [[ "$status" == "CREATE_COMPLETE" || "$status" == "UPDATE_COMPLETE" ]]; then
                validation_results+=("✅ $stack: $status")
            else
                validation_results+=("❌ $stack: $status")
            fi
        else
            validation_results+=("❌ $stack: NOT_FOUND")
        fi
    done
    
    # Display results
    echo -e "${BLUE}📊 Validation Results:${NC}"
    for result in "${validation_results[@]}"; do
        echo "  $result"
    done
    
    # Test connectivity
    echo -e "${YELLOW}🔗 Testing VPN connectivity${NC}"
    test_vpn_connectivity
}

# Function to test VPN connectivity
test_vpn_connectivity() {
    # Invoke VPN validation Lambda function
    local function_name="${PROJECT_NAME}-vpn-validation"
    
    if aws lambda get-function --function-name "$function_name" --profile $GOVCLOUD_PROFILE &>/dev/null; then
        echo "Testing VPN connectivity via Lambda function..."
        local result=$(aws lambda invoke \
            --function-name "$function_name" \
            --profile $GOVCLOUD_PROFILE \
            --payload '{}' \
            --cli-binary-format raw-in-base64-out \
            /tmp/vpn-test-result.json)
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ VPN connectivity test completed${NC}"
            echo "Results saved to: /tmp/vpn-test-result.json"
        else
            echo -e "${RED}❌ VPN connectivity test failed${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  VPN validation function not found, skipping connectivity test${NC}"
    fi
}

# Function to rollback deployment
rollback_deployment() {
    echo -e "${YELLOW}🔄 Rolling back deployment${NC}"
    
    read -p "Are you sure you want to rollback the entire deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Rollback cancelled"
        exit 0
    fi
    
    # Delete stacks in reverse order
    local rollback_order=(
        "monitoring:$GOVCLOUD_PROFILE:$COMMERCIAL_PROFILE"
        "security:$GOVCLOUD_PROFILE"
        "lambda:$GOVCLOUD_PROFILE"
        "vpn:$GOVCLOUD_PROFILE:$COMMERCIAL_PROFILE"
        "endpoints:$GOVCLOUD_PROFILE:$COMMERCIAL_PROFILE"
        "vpc:$GOVCLOUD_PROFILE:$COMMERCIAL_PROFILE"
    )
    
    for item in "${rollback_order[@]}"; do
        IFS=':' read -r phase profiles <<< "$item"
        IFS=':' read -r -a profile_array <<< "$profiles"
        
        for profile in "${profile_array[@]}"; do
            local partition=$([ "$profile" == "$GOVCLOUD_PROFILE" ] && echo "govcloud" || echo "commercial")
            local stack_name="${PROJECT_NAME}-${partition}-${phase}"
            
            if aws cloudformation describe-stacks --stack-name "$stack_name" --profile $profile &>/dev/null; then
                echo "Deleting stack: $stack_name"
                aws cloudformation delete-stack --stack-name "$stack_name" --profile $profile
                aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --profile $profile
                echo -e "${GREEN}✅ Deleted: $stack_name${NC}"
            fi
        done
    done
    
    echo -e "${GREEN}🎉 Rollback completed${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Deployment Configuration:${NC}"
    echo "  Phase: $DEPLOYMENT_PHASE"
    echo "  Environment: $ENVIRONMENT"
    echo "  Rollback: $ROLLBACK"
    echo "  Validate Only: $VALIDATE_ONLY"
    echo ""
    
    if [ "$ROLLBACK" = true ]; then
        rollback_deployment
        exit 0
    fi
    
    check_prerequisites
    
    if [ "$VALIDATE_ONLY" = true ]; then
        validate_deployment
        exit 0
    fi
    
    # Upload templates
    DEPLOYMENT_BUCKET=$(upload_templates $GOVCLOUD_PROFILE "GovCloud")
    upload_templates $COMMERCIAL_PROFILE "Commercial" >/dev/null
    
    # Deploy phases
    if [ "$DEPLOYMENT_PHASE" = "all" ] || [ "$DEPLOYMENT_PHASE" = "vpc" ]; then
        deploy_phase $GOVCLOUD_PROFILE "GovCloud" "vpc" "vpn-govcloud-vpc.yaml"
        deploy_phase $COMMERCIAL_PROFILE "Commercial" "vpc" "vpn-commercial-vpc.yaml"
    fi
    
    if [ "$DEPLOYMENT_PHASE" = "all" ] || [ "$DEPLOYMENT_PHASE" = "endpoints" ]; then
        deploy_phase $GOVCLOUD_PROFILE "GovCloud" "endpoints" "vpn-govcloud-endpoints.yaml" "vpc"
        deploy_phase $COMMERCIAL_PROFILE "Commercial" "endpoints" "vpn-commercial-endpoints.yaml" "vpc"
    fi
    
    if [ "$DEPLOYMENT_PHASE" = "all" ] || [ "$DEPLOYMENT_PHASE" = "vpn" ]; then
        deploy_phase $GOVCLOUD_PROFILE "GovCloud" "vpn" "vpn-gateway.yaml" "endpoints"
        deploy_phase $COMMERCIAL_PROFILE "Commercial" "vpn" "vpn-gateway.yaml" "endpoints"
    fi
    
    if [ "$DEPLOYMENT_PHASE" = "all" ] || [ "$DEPLOYMENT_PHASE" = "lambda" ]; then
        deploy_phase $GOVCLOUD_PROFILE "GovCloud" "lambda" "vpn-lambda-function.yaml" "endpoints"
    fi
    
    if [ "$DEPLOYMENT_PHASE" = "all" ] || [ "$DEPLOYMENT_PHASE" = "security" ]; then
        deploy_phase $GOVCLOUD_PROFILE "GovCloud" "security" "vpn-security-controls.yaml" "vpn"
        deploy_phase $GOVCLOUD_PROFILE "GovCloud" "audit" "vpn-audit-compliance.yaml" "security"
    fi
    
    if [ "$DEPLOYMENT_PHASE" = "all" ] || [ "$DEPLOYMENT_PHASE" = "monitoring" ]; then
        deploy_phase $GOVCLOUD_PROFILE "GovCloud" "monitoring" "vpn-monitoring-alerting.yaml" "lambda"
        deploy_phase $COMMERCIAL_PROFILE "Commercial" "monitoring" "vpn-monitoring-alerting.yaml" "vpn"
    fi
    
    # Validate deployment
    validate_deployment
    
    echo -e "${GREEN}🎉 VPN solution deployment completed successfully!${NC}"
    echo ""
    
    # Auto-generate configuration if extract script is available
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/extract-vpn-config.sh" ]; then
        echo -e "${YELLOW}🔧 Auto-generating VPN configuration...${NC}"
        
        if "${SCRIPT_DIR}/extract-vpn-config.sh" \
            --project-name "$PROJECT_NAME" \
            --environment "$ENVIRONMENT" \
            --govcloud-profile "$GOVCLOUD_PROFILE" \
            --commercial-profile "$COMMERCIAL_PROFILE"; then
            
            echo -e "${GREEN}✅ VPN configuration generated successfully${NC}"
            
            # Auto-load configuration if in current directory
            if [ -f "./config-vpn.sh" ]; then
                echo -e "${YELLOW}🔄 Auto-loading configuration...${NC}"
                source "./config-vpn.sh"
                echo -e "${GREEN}✅ Configuration loaded and ready to use${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️ Configuration generation failed, but deployment completed${NC}"
        fi
    fi
    
    echo -e "${BLUE}📋 Next Steps:${NC}"
    echo "1. Load the configuration: source config-vpn.sh"
    echo "2. Validate the setup: validate_vpn_config"
    echo "3. Test VPN connectivity: test_vpn_connectivity"
    echo "4. Test the Lambda function: aws lambda invoke --function-name \$LAMBDA_FUNCTION_NAME response.json"
    echo "5. Monitor VPN status: ${SCRIPT_DIR}/get-vpn-status.sh watch"
    echo "6. Review monitoring dashboard: echo \$MONITORING_DASHBOARD_URL"
}

# Run main function
main "$@"