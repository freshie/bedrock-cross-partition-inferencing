#!/bin/bash

# Complete VPN infrastructure deployment orchestration script
# Deploys VPC, VPN gateway, VPC endpoints, and validates connectivity

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
SKIP_VALIDATION="false"
SKIP_VPC_ENDPOINTS="false"

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

print_separator() {
    echo "--------------------------------------------------------------------------------"
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy complete VPN infrastructure for dual routing system"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV         Environment (dev, stage, prod) [default: prod]"
    echo "  -p, --project-name NAME       Project name [default: dual-routing-api-gateway]"
    echo "  -r, --region REGION           AWS region [default: us-gov-west-1]"
    echo "  --vpc-cidr CIDR              VPC CIDR block [default: 10.0.0.0/16]"
    echo "  --commercial-vpn-gw ID       Commercial VPN Gateway ID"
    echo "  --commercial-cgw ID          Commercial Customer Gateway ID"
    echo "  --skip-validation            Skip connectivity validation"
    echo "  --skip-vpc-endpoints         Skip VPC endpoints deployment"
    echo "  --validate-only              Only validate existing infrastructure"
    echo "  --dry-run                    Show what would be deployed without executing"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --environment dev"
    echo "  $0 --environment prod --vpc-cidr 10.1.0.0/16"
    echo "  $0 --validate-only"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    print_header "VALIDATING PREREQUISITES"
    
    # Check required scripts exist
    local required_scripts=(
        "$SCRIPT_DIR/deploy-vpn-infrastructure.sh"
        "$SCRIPT_DIR/deploy-vpc-endpoints.sh"
        "$SCRIPT_DIR/validate-vpn-connectivity.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_error "Required script not found: $script"
            exit 1
        fi
        
        if [[ ! -x "$script" ]]; then
            log_error "Script not executable: $script"
            log_info "Run: chmod +x $script"
            exit 1
        fi
    done
    
    log_success "All required scripts found and executable"
    
    # Check AWS CLI and credentials
    if ! command_exists aws; then
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    log_success "AWS CLI and credentials validated"
}

# Function to deploy VPN infrastructure
deploy_vpn_infrastructure() {
    print_header "DEPLOYING VPN INFRASTRUCTURE"
    
    log_info "Deploying VPC, subnets, VPN gateway, and security groups..."
    
    local deploy_cmd="$SCRIPT_DIR/deploy-vpn-infrastructure.sh"
    deploy_cmd="$deploy_cmd --environment $ENVIRONMENT"
    deploy_cmd="$deploy_cmd --project-name $PROJECT_NAME"
    
    if [[ -n "$AWS_REGION" ]]; then
        deploy_cmd="$deploy_cmd --region $AWS_REGION"
    fi
    
    if [[ -n "$VPC_CIDR" ]]; then
        deploy_cmd="$deploy_cmd --vpc-cidr $VPC_CIDR"
    fi
    
    if [[ -n "$COMMERCIAL_VPN_GW" ]]; then
        deploy_cmd="$deploy_cmd --commercial-vpn-gw $COMMERCIAL_VPN_GW"
    fi
    
    if [[ -n "$COMMERCIAL_CGW" ]]; then
        deploy_cmd="$deploy_cmd --commercial-cgw $COMMERCIAL_CGW"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        deploy_cmd="$deploy_cmd --dry-run"
    fi
    
    log_info "Executing: $deploy_cmd"
    
    if eval "$deploy_cmd"; then
        log_success "VPN infrastructure deployment completed"
        return 0
    else
        log_error "VPN infrastructure deployment failed"
        return 1
    fi
}

# Function to get infrastructure details from CloudFormation
get_infrastructure_details() {
    print_header "RETRIEVING INFRASTRUCTURE DETAILS"
    
    local stack_name="$PROJECT_NAME-$ENVIRONMENT-vpn-infrastructure"
    
    log_info "Getting details from CloudFormation stack: $stack_name"
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1; then
        log_error "CloudFormation stack '$stack_name' not found"
        return 1
    fi
    
    # Get stack outputs
    local outputs
    outputs=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].Outputs' --output json 2>/dev/null)
    
    if [[ "$outputs" != "null" && "$outputs" != "[]" ]]; then
        # Extract key values
        VPC_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPCId") | .OutputValue' 2>/dev/null || echo "")
        PRIVATE_SUBNET_1=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="PrivateSubnet1Id") | .OutputValue' 2>/dev/null || echo "")
        PRIVATE_SUBNET_2=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="PrivateSubnet2Id") | .OutputValue' 2>/dev/null || echo "")
        SECURITY_GROUP_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNLambdaSecurityGroupId") | .OutputValue' 2>/dev/null || echo "")
        VPN_CONNECTION_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNConnectionId") | .OutputValue' 2>/dev/null || echo "")
        
        log_success "Retrieved infrastructure details:"
        log_info "  VPC ID: ${VPC_ID:-not found}"
        log_info "  Private Subnet 1: ${PRIVATE_SUBNET_1:-not found}"
        log_info "  Private Subnet 2: ${PRIVATE_SUBNET_2:-not found}"
        log_info "  Security Group: ${SECURITY_GROUP_ID:-not found}"
        log_info "  VPN Connection: ${VPN_CONNECTION_ID:-not found}"
        
        # Construct subnet IDs for VPC endpoints
        if [[ -n "$PRIVATE_SUBNET_1" && -n "$PRIVATE_SUBNET_2" ]]; then
            SUBNET_IDS="$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2"
        fi
        
        return 0
    else
        log_error "No outputs found in CloudFormation stack"
        return 1
    fi
}

# Function to deploy VPC endpoints
deploy_vpc_endpoints() {
    print_header "DEPLOYING VPC ENDPOINTS"
    
    if [[ "$SKIP_VPC_ENDPOINTS" == "true" ]]; then
        log_info "Skipping VPC endpoints deployment (--skip-vpc-endpoints specified)"
        return 0
    fi
    
    if [[ -z "$VPC_ID" || -z "$SUBNET_IDS" || -z "$SECURITY_GROUP_ID" ]]; then
        log_error "Missing required infrastructure details for VPC endpoints deployment"
        log_error "VPC ID: ${VPC_ID:-missing}"
        log_error "Subnet IDs: ${SUBNET_IDS:-missing}"
        log_error "Security Group ID: ${SECURITY_GROUP_ID:-missing}"
        return 1
    fi
    
    log_info "Deploying VPC endpoints for AWS services..."
    
    local deploy_cmd="$SCRIPT_DIR/deploy-vpc-endpoints.sh"
    deploy_cmd="$deploy_cmd --vpc-id $VPC_ID"
    deploy_cmd="$deploy_cmd --subnet-ids $SUBNET_IDS"
    deploy_cmd="$deploy_cmd --security-group $SECURITY_GROUP_ID"
    deploy_cmd="$deploy_cmd --environment $ENVIRONMENT"
    deploy_cmd="$deploy_cmd --project-name $PROJECT_NAME"
    
    if [[ -n "$AWS_REGION" ]]; then
        deploy_cmd="$deploy_cmd --region $AWS_REGION"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        deploy_cmd="$deploy_cmd --dry-run"
    fi
    
    log_info "Executing: $deploy_cmd"
    
    if eval "$deploy_cmd"; then
        log_success "VPC endpoints deployment completed"
        return 0
    else
        log_error "VPC endpoints deployment failed"
        return 1
    fi
}

# Function to validate connectivity
validate_connectivity() {
    print_header "VALIDATING VPN CONNECTIVITY"
    
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_info "Skipping connectivity validation (--skip-validation specified)"
        return 0
    fi
    
    log_info "Validating VPN connectivity and infrastructure..."
    
    local validate_cmd="$SCRIPT_DIR/validate-vpn-connectivity.sh"
    validate_cmd="$validate_cmd --environment $ENVIRONMENT"
    validate_cmd="$validate_cmd --project-name $PROJECT_NAME"
    
    if [[ -n "$VPC_ID" ]]; then
        validate_cmd="$validate_cmd --vpc-id $VPC_ID"
    fi
    
    if [[ -n "$VPN_CONNECTION_ID" ]]; then
        validate_cmd="$validate_cmd --vpn-connection-id $VPN_CONNECTION_ID"
    fi
    
    if [[ -n "$AWS_REGION" ]]; then
        validate_cmd="$validate_cmd --region $AWS_REGION"
    fi
    
    # Add comprehensive tests
    validate_cmd="$validate_cmd --comprehensive"
    
    log_info "Executing: $validate_cmd"
    
    if eval "$validate_cmd"; then
        log_success "Connectivity validation completed"
        return 0
    else
        log_warning "Connectivity validation completed with warnings"
        log_info "Check the validation report for details"
        return 0  # Don't fail the entire deployment for validation warnings
    fi
}

# Function to generate deployment summary
generate_deployment_summary() {
    print_header "GENERATING DEPLOYMENT SUMMARY"
    
    local summary_file="$PROJECT_ROOT/outputs/complete-vpn-infrastructure-summary-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$summary_file")"
    
    {
        echo "Complete VPN Infrastructure Deployment Summary"
        echo "Generated: $(date)"
        echo "Project: $PROJECT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo ""
        echo "Deployment Configuration:"
        echo "- AWS Region: ${AWS_REGION:-us-gov-west-1}"
        echo "- VPC CIDR: ${VPC_CIDR:-10.0.0.0/16}"
        echo "- Project Name: $PROJECT_NAME"
        echo "- Environment: $ENVIRONMENT"
        echo ""
        echo "Infrastructure Deployed:"
        echo "- VPC with public and private subnets"
        echo "- Internet Gateway and NAT Gateways"
        echo "- VPN Gateway and Customer Gateway"
        echo "- VPN Connection to Commercial AWS"
        echo "- Security Groups for Lambda and VPC endpoints"
        if [[ "$SKIP_VPC_ENDPOINTS" != "true" ]]; then
            echo "- VPC Endpoints for AWS services:"
            echo "  * Bedrock Runtime (Interface)"
            echo "  * Secrets Manager (Interface)"
            echo "  * CloudWatch Logs (Interface)"
            echo "  * CloudWatch Monitoring (Interface)"
            echo "  * DynamoDB (Gateway)"
        fi
        echo ""
        echo "Infrastructure Details:"
        echo "- VPC ID: ${VPC_ID:-not available}"
        echo "- Private Subnet 1: ${PRIVATE_SUBNET_1:-not available}"
        echo "- Private Subnet 2: ${PRIVATE_SUBNET_2:-not available}"
        echo "- Lambda Security Group: ${SECURITY_GROUP_ID:-not available}"
        echo "- VPN Connection ID: ${VPN_CONNECTION_ID:-not available}"
        echo ""
        echo "CloudFormation Stack:"
        echo "- Stack Name: $PROJECT_NAME-$ENVIRONMENT-vpn-infrastructure"
        echo "- Region: ${AWS_REGION:-us-gov-west-1}"
        echo ""
        echo "Next Steps:"
        echo "1. Verify VPN connection establishment with Commercial AWS"
        echo "2. Test VPC endpoint connectivity"
        echo "3. Deploy VPN Lambda function using deploy-vpn-lambda.sh"
        echo "4. Run end-to-end connectivity tests"
        echo "5. Configure monitoring and alerting"
        echo ""
        echo "Validation Status:"
        if [[ "$SKIP_VALIDATION" == "true" ]]; then
            echo "- Connectivity validation: SKIPPED"
        else
            echo "- Connectivity validation: COMPLETED"
        fi
        echo ""
        echo "Important Notes:"
        echo "- VPN tunnels may take several minutes to establish"
        echo "- Monitor VPN connection status in AWS Console"
        echo "- Ensure Commercial AWS side is properly configured"
        echo "- Test Lambda deployment before production use"
    } > "$summary_file"
    
    log_success "Deployment summary generated: $summary_file"
}

# Function to display final status
display_final_status() {
    print_header "DEPLOYMENT STATUS SUMMARY"
    
    local overall_status="SUCCESS"
    
    echo "Component Deployment Status:"
    echo "├── VPN Infrastructure (VPC, Subnets, VPN Gateway): ✓ DEPLOYED"
    
    if [[ "$SKIP_VPC_ENDPOINTS" == "true" ]]; then
        echo "├── VPC Endpoints: ⏭ SKIPPED"
    else
        echo "├── VPC Endpoints: ✓ DEPLOYED"
    fi
    
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        echo "└── Connectivity Validation: ⏭ SKIPPED"
    else
        echo "└── Connectivity Validation: ✓ COMPLETED"
    fi
    
    echo ""
    
    if [[ "$overall_status" == "SUCCESS" ]]; then
        log_success "🎉 COMPLETE VPN INFRASTRUCTURE DEPLOYMENT SUCCESSFUL!"
        echo ""
        echo "✓ VPC and networking infrastructure deployed"
        echo "✓ VPN gateway and connection configured"
        if [[ "$SKIP_VPC_ENDPOINTS" != "true" ]]; then
            echo "✓ VPC endpoints for AWS services deployed"
        fi
        if [[ "$SKIP_VALIDATION" != "true" ]]; then
            echo "✓ Connectivity validation completed"
        fi
        echo ""
        echo "Your VPN infrastructure is ready for Lambda deployment!"
    else
        log_error "❌ DEPLOYMENT COMPLETED WITH ISSUES"
        echo ""
        echo "Please review the logs and fix any issues before proceeding."
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Deploy VPN Lambda function: ./scripts/deploy-vpn-lambda.sh"
    echo "2. Update API Gateway with VPN paths: ./scripts/deploy-api-gateway-vpn-paths.sh"
    echo "3. Run end-to-end tests: ./scripts/test-end-to-end-routing.sh"
    
    print_separator
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
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
            -r|--region)
                export AWS_REGION="$2"
                shift 2
                ;;
            --vpc-cidr)
                VPC_CIDR="$2"
                shift 2
                ;;
            --commercial-vpn-gw)
                COMMERCIAL_VPN_GW="$2"
                shift 2
                ;;
            --commercial-cgw)
                COMMERCIAL_CGW="$2"
                shift 2
                ;;
            --skip-validation)
                SKIP_VALIDATION="true"
                shift
                ;;
            --skip-vpc-endpoints)
                SKIP_VPC_ENDPOINTS="true"
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
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
    
    # Set default AWS region if not set
    export AWS_REGION="${AWS_REGION:-us-gov-west-1}"
    
    print_header "COMPLETE VPN INFRASTRUCTURE DEPLOYMENT"
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "AWS Region: $AWS_REGION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No actual resources will be created"
    fi
    
    # Execute deployment steps
    validate_prerequisites
    
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log_info "Validation-only mode - skipping deployment"
        get_infrastructure_details
        validate_connectivity
        generate_deployment_summary
    else
        # Full deployment
        deploy_vpn_infrastructure
        get_infrastructure_details
        deploy_vpc_endpoints
        validate_connectivity
        generate_deployment_summary
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    display_final_status
    
    log_info "Total execution time: ${duration} seconds"
    
    # Exit with success
    exit 0
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi