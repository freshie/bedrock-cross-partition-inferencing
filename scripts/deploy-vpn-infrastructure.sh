#!/bin/bash

# Deployment script for VPN infrastructure
# Deploys VPC, subnets, VPN gateway, and VPC endpoints for dual routing system

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INFRASTRUCTURE_DIR="$PROJECT_ROOT/infrastructure"

# Default configuration
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
STACK_NAME="$PROJECT_NAME-$ENVIRONMENT-vpn-infrastructure"
TEMPLATE_FILE="$INFRASTRUCTURE_DIR/dual-routing-vpn-infrastructure.yaml"

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
    echo "Deploy VPN infrastructure for dual routing system"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV     Environment (dev, stage, prod) [default: prod]"
    echo "  -p, --project-name NAME   Project name [default: dual-routing-api-gateway]"
    echo "  -r, --region REGION       AWS region [default: us-gov-west-1]"
    echo "  --vpc-cidr CIDR          VPC CIDR block [default: 10.0.0.0/16]"
    echo "  --commercial-vpn-gw ID   Commercial VPN Gateway ID"
    echo "  --commercial-cgw ID      Commercial Customer Gateway ID"
    echo "  --validate-only          Only validate template, don't deploy"
    echo "  --dry-run                Show what would be deployed without executing"
    echo "  -h, --help               Show this help message"
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
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    
    log_success "AWS CLI found: $(aws --version)"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid."
        log_error "Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi
    
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
    USER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
    
    log_success "AWS credentials validated"
    log_info "Account ID: $ACCOUNT_ID"
    log_info "User/Role: $USER_ARN"
    
    # Check if template file exists
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        log_error "CloudFormation template not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    log_success "CloudFormation template found: $TEMPLATE_FILE"
    
    # Check jq for JSON parsing
    if ! command_exists jq; then
        log_warning "jq not found. Some features may be limited."
        log_warning "Install jq for better JSON parsing: https://stedolan.github.io/jq/"
    fi
}

# Function to validate CloudFormation template
validate_template() {
    print_header "VALIDATING CLOUDFORMATION TEMPLATE"
    
    log_info "Validating template syntax..."
    
    if aws cloudformation validate-template --template-body "file://$TEMPLATE_FILE" >/dev/null 2>&1; then
        log_success "CloudFormation template is valid"
    else
        log_error "CloudFormation template validation failed"
        aws cloudformation validate-template --template-body "file://$TEMPLATE_FILE"
        exit 1
    fi
    
    # Check template size
    TEMPLATE_SIZE=$(wc -c < "$TEMPLATE_FILE")
    MAX_SIZE=51200  # 50KB limit for template body
    
    if [[ $TEMPLATE_SIZE -gt $MAX_SIZE ]]; then
        log_warning "Template size ($TEMPLATE_SIZE bytes) is large. Consider using S3 for templates over 50KB."
    else
        log_info "Template size: $TEMPLATE_SIZE bytes"
    fi
}

# Function to check if stack exists
stack_exists() {
    aws cloudformation describe-stacks --stack-name "$1" >/dev/null 2>&1
}

# Function to get stack status
get_stack_status() {
    aws cloudformation describe-stacks --stack-name "$1" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND"
}

# Function to wait for stack operation
wait_for_stack() {
    local stack_name="$1"
    local operation="$2"
    
    log_info "Waiting for stack $operation to complete..."
    
    local start_time=$(date +%s)
    local timeout=1800  # 30 minutes
    
    while true; do
        local status=$(get_stack_status "$stack_name")
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        case "$status" in
            *_COMPLETE)
                log_success "Stack $operation completed successfully"
                return 0
                ;;
            *_FAILED|*_ROLLBACK_COMPLETE)
                log_error "Stack $operation failed with status: $status"
                return 1
                ;;
            *_IN_PROGRESS)
                if [[ $elapsed -gt $timeout ]]; then
                    log_error "Stack $operation timed out after $timeout seconds"
                    return 1
                fi
                echo -n "."
                sleep 30
                ;;
            *)
                log_error "Unknown stack status: $status"
                return 1
                ;;
        esac
    done
}

# Function to deploy stack
deploy_stack() {
    print_header "DEPLOYING VPN INFRASTRUCTURE STACK"
    
    # Prepare parameters
    local parameters=(
        "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
    )
    
    # Add optional parameters if provided
    if [[ -n "$VPC_CIDR" ]]; then
        parameters+=("ParameterKey=VpcCidr,ParameterValue=$VPC_CIDR")
    fi
    
    if [[ -n "$COMMERCIAL_VPN_GW" ]]; then
        parameters+=("ParameterKey=CommercialVpnGatewayId,ParameterValue=$COMMERCIAL_VPN_GW")
    fi
    
    if [[ -n "$COMMERCIAL_CGW" ]]; then
        parameters+=("ParameterKey=CommercialCustomerGatewayId,ParameterValue=$COMMERCIAL_CGW")
    fi
    
    # Convert parameters array to string
    local param_string=""
    for param in "${parameters[@]}"; do
        if [[ -n "$param_string" ]]; then
            param_string="$param_string $param"
        else
            param_string="$param"
        fi
    done
    
    log_info "Stack Name: $STACK_NAME"
    log_info "Template: $TEMPLATE_FILE"
    log_info "Parameters: $param_string"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would deploy stack with above configuration"
        return 0
    fi
    
    # Check if stack exists
    if stack_exists "$STACK_NAME"; then
        local current_status=$(get_stack_status "$STACK_NAME")
        log_info "Stack exists with status: $current_status"
        
        case "$current_status" in
            *_COMPLETE)
                log_info "Updating existing stack..."
                aws cloudformation update-stack \
                    --stack-name "$STACK_NAME" \
                    --template-body "file://$TEMPLATE_FILE" \
                    --parameters $param_string \
                    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
                    --tags Key=Project,Value="$PROJECT_NAME" Key=Environment,Value="$ENVIRONMENT" Key=ManagedBy,Value=CloudFormation
                
                if wait_for_stack "$STACK_NAME" "update"; then
                    log_success "Stack update completed successfully"
                else
                    log_error "Stack update failed"
                    return 1
                fi
                ;;
            *_IN_PROGRESS)
                log_error "Stack is currently in progress. Please wait for current operation to complete."
                return 1
                ;;
            *_FAILED)
                log_error "Stack is in failed state. Please check the stack events and fix issues."
                return 1
                ;;
        esac
    else
        log_info "Creating new stack..."
        aws cloudformation create-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters $param_string \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
            --tags Key=Project,Value="$PROJECT_NAME" Key=Environment,Value="$ENVIRONMENT" Key=ManagedBy,Value=CloudFormation \
            --enable-termination-protection
        
        if wait_for_stack "$STACK_NAME" "creation"; then
            log_success "Stack creation completed successfully"
        else
            log_error "Stack creation failed"
            return 1
        fi
    fi
}

# Function to display stack outputs
display_stack_outputs() {
    print_header "STACK OUTPUTS"
    
    if ! stack_exists "$STACK_NAME"; then
        log_warning "Stack does not exist"
        return 1
    fi
    
    log_info "Retrieving stack outputs..."
    
    local outputs
    outputs=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs' --output json 2>/dev/null)
    
    if [[ "$outputs" == "null" || "$outputs" == "[]" ]]; then
        log_warning "No outputs found for stack"
        return 0
    fi
    
    echo "$outputs" | jq -r '.[] | "  \(.OutputKey): \(.OutputValue)"'
    
    # Save outputs to file for other scripts
    local outputs_file="$PROJECT_ROOT/outputs/vpn-infrastructure-outputs.json"
    mkdir -p "$(dirname "$outputs_file")"
    echo "$outputs" > "$outputs_file"
    log_info "Outputs saved to: $outputs_file"
}

# Function to validate VPN connectivity
validate_vpn_connectivity() {
    print_header "VALIDATING VPN CONNECTIVITY"
    
    log_info "Checking VPN connection status..."
    
    # Get VPN connection ID from stack outputs
    local vpn_connection_id
    if command_exists jq; then
        vpn_connection_id=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs[?OutputKey==`VPNConnectionId`].OutputValue' --output text 2>/dev/null)
    fi
    
    if [[ -n "$vpn_connection_id" && "$vpn_connection_id" != "None" ]]; then
        log_info "VPN Connection ID: $vpn_connection_id"
        
        # Check VPN connection state
        local vpn_state
        vpn_state=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$vpn_connection_id" --query 'VpnConnections[0].State' --output text 2>/dev/null)
        
        log_info "VPN Connection State: $vpn_state"
        
        if [[ "$vpn_state" == "available" ]]; then
            log_success "VPN connection is available"
        else
            log_warning "VPN connection is not yet available. State: $vpn_state"
            log_info "This is normal for new VPN connections. It may take several minutes to establish."
        fi
        
        # Check tunnel states
        local tunnel_states
        tunnel_states=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$vpn_connection_id" --query 'VpnConnections[0].VgwTelemetry[*].Status' --output text 2>/dev/null)
        
        if [[ -n "$tunnel_states" ]]; then
            log_info "VPN Tunnel States: $tunnel_states"
        fi
    else
        log_warning "Could not retrieve VPN connection ID from stack outputs"
    fi
    
    # Validate VPC endpoints
    log_info "Validating VPC endpoints..."
    
    local vpc_id
    vpc_id=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].Outputs[?OutputKey==`VPCId`].OutputValue' --output text 2>/dev/null)
    
    if [[ -n "$vpc_id" && "$vpc_id" != "None" ]]; then
        local endpoint_count
        endpoint_count=$(aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc_id" --query 'length(VpcEndpoints)' --output text 2>/dev/null)
        
        log_info "VPC ID: $vpc_id"
        log_info "VPC Endpoints created: $endpoint_count"
        
        if [[ "$endpoint_count" -ge 5 ]]; then
            log_success "All required VPC endpoints appear to be created"
        else
            log_warning "Expected at least 5 VPC endpoints, found: $endpoint_count"
        fi
    fi
}

# Function to generate deployment report
generate_deployment_report() {
    print_header "GENERATING DEPLOYMENT REPORT"
    
    local report_file="$PROJECT_ROOT/outputs/vpn-infrastructure-deployment-report-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "VPN Infrastructure Deployment Report"
        echo "Generated: $(date)"
        echo "Project: $PROJECT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo "Stack Name: $STACK_NAME"
        echo ""
        echo "Deployment Configuration:"
        echo "- AWS Region: ${AWS_REGION:-us-gov-west-1}"
        echo "- VPC CIDR: ${VPC_CIDR:-10.0.0.0/16}"
        echo "- Template: $TEMPLATE_FILE"
        echo ""
        echo "Stack Status:"
        if stack_exists "$STACK_NAME"; then
            echo "- Status: $(get_stack_status "$STACK_NAME")"
            echo "- Stack ARN: $(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query 'Stacks[0].StackId' --output text 2>/dev/null)"
        else
            echo "- Status: NOT_DEPLOYED"
        fi
        echo ""
        echo "Resources Created:"
        echo "- VPC with public and private subnets"
        echo "- NAT Gateways for private subnet internet access"
        echo "- VPN Gateway and Customer Gateway"
        echo "- VPN Connection to Commercial AWS"
        echo "- VPC Endpoints for AWS services (Bedrock, Secrets Manager, DynamoDB, CloudWatch)"
        echo "- Security Groups for Lambda functions and VPC endpoints"
        echo ""
        echo "Next Steps:"
        echo "1. Verify VPN connection establishment with Commercial AWS"
        echo "2. Test VPC endpoint connectivity"
        echo "3. Deploy VPN Lambda function using deploy-vpn-lambda.sh"
        echo "4. Run connectivity validation tests"
    } > "$report_file"
    
    log_success "Deployment report generated: $report_file"
}

# Function to cleanup on error
cleanup_on_error() {
    if [[ "$?" -ne 0 ]]; then
        log_error "Deployment failed. Check the CloudFormation console for details."
        log_info "Stack events can be viewed with:"
        log_info "aws cloudformation describe-stack-events --stack-name $STACK_NAME"
    fi
}

# Main execution function
main() {
    # Set trap for cleanup
    trap cleanup_on_error EXIT
    
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
    
    # Update stack name with parsed parameters
    STACK_NAME="$PROJECT_NAME-$ENVIRONMENT-vpn-infrastructure"
    
    # Set default AWS region if not set
    export AWS_REGION="${AWS_REGION:-us-gov-west-1}"
    
    print_header "VPN INFRASTRUCTURE DEPLOYMENT"
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "AWS Region: $AWS_REGION"
    log_info "Stack Name: $STACK_NAME"
    
    # Execute deployment steps
    validate_prerequisites
    validate_template
    
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log_success "Template validation completed successfully"
        exit 0
    fi
    
    deploy_stack
    display_stack_outputs
    validate_vpn_connectivity
    generate_deployment_report
    
    # Remove error trap on successful completion
    trap - EXIT
    
    print_header "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "VPN infrastructure has been deployed successfully"
    log_info "Stack Name: $STACK_NAME"
    log_info "Next steps:"
    log_info "1. Verify VPN connection with Commercial AWS"
    log_info "2. Deploy VPN Lambda function"
    log_info "3. Run connectivity tests"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi