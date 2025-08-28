#!/bin/bash

# Validation script for VPN connectivity
# Verifies VPN connection, VPC endpoints, and network connectivity before Lambda deployment

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
VPC_ID=""
VPN_CONNECTION_ID=""

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
    echo "Validate VPN connectivity for dual routing system"
    echo ""
    echo "Options:"
    echo "  -v, --vpc-id VPC_ID               VPC ID to validate"
    echo "  -c, --vpn-connection-id ID        VPN Connection ID to validate"
    echo "  -e, --environment ENV             Environment (dev, stage, prod) [default: prod]"
    echo "  -p, --project-name NAME           Project name [default: dual-routing-api-gateway]"
    echo "  -r, --region REGION               AWS region [default: us-gov-west-1]"
    echo "  --stack-name STACK_NAME           CloudFormation stack name to get resources from"
    echo "  --comprehensive                   Run comprehensive connectivity tests"
    echo "  --report-only                     Generate report without running tests"
    echo "  -h, --help                        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --stack-name dual-routing-api-gateway-prod-vpn-infrastructure"
    echo "  $0 --vpc-id vpc-12345 --vpn-connection-id vpn-67890"
    echo "  $0 --comprehensive"
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
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity)
    local account_id
    account_id=$(echo "$caller_identity" | jq -r '.Account' 2>/dev/null || echo "unknown")
    
    log_success "AWS credentials validated (Account: $account_id)"
    
    # Check jq for JSON parsing
    if ! command_exists jq; then
        log_warning "jq not found. Some features may be limited."
        log_warning "Install jq for better JSON parsing: https://stedolan.github.io/jq/"
    fi
}

# Function to get resources from CloudFormation stack
get_stack_resources() {
    local stack_name="$1"
    
    if [[ -z "$stack_name" ]]; then
        return 0
    fi
    
    log_info "Retrieving resources from CloudFormation stack: $stack_name"
    
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
        VPN_CONNECTION_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNConnectionId") | .OutputValue' 2>/dev/null || echo "")
        
        log_success "Retrieved resources from stack:"
        log_info "  VPC ID: ${VPC_ID:-not found}"
        log_info "  VPN Connection ID: ${VPN_CONNECTION_ID:-not found}"
    else
        log_warning "No outputs found in CloudFormation stack"
    fi
}

# Function to validate VPC configuration
validate_vpc_configuration() {
    print_header "VALIDATING VPC CONFIGURATION"
    
    if [[ -z "$VPC_ID" ]]; then
        log_warning "VPC ID not provided, skipping VPC validation"
        return 0
    fi
    
    log_info "Validating VPC: $VPC_ID"
    
    # Check if VPC exists
    local vpc_info
    vpc_info=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --output json 2>/dev/null)
    
    if [[ -z "$vpc_info" || "$vpc_info" == "null" ]]; then
        log_error "VPC $VPC_ID not found"
        return 1
    fi
    
    local vpc_state
    vpc_state=$(echo "$vpc_info" | jq -r '.Vpcs[0].State' 2>/dev/null)
    
    if [[ "$vpc_state" == "available" ]]; then
        log_success "VPC $VPC_ID is available"
    else
        log_error "VPC $VPC_ID is not available (State: $vpc_state)"
        return 1
    fi
    
    # Check subnets
    local subnet_count
    subnet_count=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'length(Subnets)' --output text 2>/dev/null)
    
    log_info "Subnets in VPC: $subnet_count"
    
    if [[ "$subnet_count" -ge 2 ]]; then
        log_success "Sufficient subnets found for Lambda deployment"
    else
        log_warning "Only $subnet_count subnets found. At least 2 recommended for high availability."
    fi
    
    # Check private subnets
    local private_subnet_count
    private_subnet_count=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Type,Values=Private" \
        --query 'length(Subnets)' --output text 2>/dev/null)
    
    log_info "Private subnets in VPC: $private_subnet_count"
    
    if [[ "$private_subnet_count" -ge 2 ]]; then
        log_success "Sufficient private subnets found for VPN Lambda deployment"
    else
        log_warning "Only $private_subnet_count private subnets found."
    fi
}

# Function to validate VPN connection
validate_vpn_connection() {
    print_header "VALIDATING VPN CONNECTION"
    
    if [[ -z "$VPN_CONNECTION_ID" ]]; then
        log_warning "VPN Connection ID not provided, skipping VPN validation"
        return 0
    fi
    
    log_info "Validating VPN Connection: $VPN_CONNECTION_ID"
    
    # Check if VPN connection exists
    local vpn_info
    vpn_info=$(aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_CONNECTION_ID" --output json 2>/dev/null)
    
    if [[ -z "$vpn_info" || "$vpn_info" == "null" ]]; then
        log_error "VPN Connection $VPN_CONNECTION_ID not found"
        return 1
    fi
    
    local vpn_state
    vpn_state=$(echo "$vpn_info" | jq -r '.VpnConnections[0].State' 2>/dev/null)
    
    log_info "VPN Connection State: $vpn_state"
    
    case "$vpn_state" in
        "available")
            log_success "VPN Connection is available"
            ;;
        "pending")
            log_warning "VPN Connection is still pending. This is normal for new connections."
            ;;
        "deleting"|"deleted")
            log_error "VPN Connection is being deleted or has been deleted"
            return 1
            ;;
        *)
            log_warning "VPN Connection is in state: $vpn_state"
            ;;
    esac
    
    # Check tunnel states
    local tunnel_states
    tunnel_states=$(echo "$vpn_info" | jq -r '.VpnConnections[0].VgwTelemetry[].Status' 2>/dev/null)
    
    if [[ -n "$tunnel_states" ]]; then
        log_info "VPN Tunnel States:"
        local tunnel_count=1
        while IFS= read -r tunnel_state; do
            log_info "  Tunnel $tunnel_count: $tunnel_state"
            ((tunnel_count++))
        done <<< "$tunnel_states"
        
        # Check if at least one tunnel is UP
        if echo "$tunnel_states" | grep -q "UP"; then
            log_success "At least one VPN tunnel is UP"
        else
            log_warning "No VPN tunnels are currently UP"
            log_info "This may be normal if the connection is still establishing"
        fi
    else
        log_warning "No tunnel telemetry data available"
    fi
    
    # Check routes
    local route_count
    route_count=$(echo "$vpn_info" | jq -r '.VpnConnections[0].Routes | length' 2>/dev/null)
    
    if [[ "$route_count" -gt 0 ]]; then
        log_info "VPN Routes configured: $route_count"
        
        # List routes
        local routes
        routes=$(echo "$vpn_info" | jq -r '.VpnConnections[0].Routes[] | "\(.DestinationCidrBlock) -> \(.State)"' 2>/dev/null)
        
        if [[ -n "$routes" ]]; then
            log_info "VPN Routes:"
            while IFS= read -r route; do
                log_info "  $route"
            done <<< "$routes"
        fi
    else
        log_warning "No VPN routes configured"
    fi
}

# Function to validate VPC endpoints
validate_vpc_endpoints() {
    print_header "VALIDATING VPC ENDPOINTS"
    
    if [[ -z "$VPC_ID" ]]; then
        log_warning "VPC ID not provided, skipping VPC endpoint validation"
        return 0
    fi
    
    log_info "Validating VPC endpoints in VPC: $VPC_ID"
    
    local region="${AWS_REGION:-us-gov-west-1}"
    local required_endpoints=(
        "com.amazonaws.$region.bedrock-runtime"
        "com.amazonaws.$region.secretsmanager"
        "com.amazonaws.$region.logs"
        "com.amazonaws.$region.monitoring"
        "com.amazonaws.$region.dynamodb"
    )
    
    local endpoint_status=()
    local available_count=0
    
    for service in "${required_endpoints[@]}"; do
        local endpoint_info
        endpoint_info=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=$service" \
            --query 'VpcEndpoints[0]' --output json 2>/dev/null)
        
        if [[ "$endpoint_info" != "null" && -n "$endpoint_info" ]]; then
            local endpoint_state
            endpoint_state=$(echo "$endpoint_info" | jq -r '.State' 2>/dev/null)
            
            if [[ "$endpoint_state" == "available" ]]; then
                log_success "VPC endpoint available: $service"
                endpoint_status+=("$service:available")
                ((available_count++))
            else
                log_warning "VPC endpoint not available: $service (State: $endpoint_state)"
                endpoint_status+=("$service:$endpoint_state")
            fi
        else
            log_error "VPC endpoint missing: $service"
            endpoint_status+=("$service:missing")
        fi
    done
    
    log_info "VPC endpoints available: $available_count/${#required_endpoints[@]}"
    
    if [[ $available_count -eq ${#required_endpoints[@]} ]]; then
        log_success "All required VPC endpoints are available"
        return 0
    else
        log_warning "Some VPC endpoints are missing or not available"
        return 1
    fi
}

# Function to validate security groups
validate_security_groups() {
    print_header "VALIDATING SECURITY GROUPS"
    
    if [[ -z "$VPC_ID" ]]; then
        log_warning "VPC ID not provided, skipping security group validation"
        return 0
    fi
    
    log_info "Validating security groups in VPC: $VPC_ID"
    
    # Find Lambda security group
    local lambda_sg_id
    lambda_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*vpn-lambda*" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    
    if [[ -n "$lambda_sg_id" && "$lambda_sg_id" != "None" ]]; then
        log_success "VPN Lambda security group found: $lambda_sg_id"
        
        # Check egress rules
        local egress_rules
        egress_rules=$(aws ec2 describe-security-groups --group-ids "$lambda_sg_id" \
            --query 'SecurityGroups[0].IpPermissionsEgress[?IpProtocol==`tcp` && FromPort==`443`]' \
            --output json 2>/dev/null)
        
        if [[ "$egress_rules" != "[]" && "$egress_rules" != "null" ]]; then
            log_success "HTTPS egress rules configured for Lambda security group"
        else
            log_warning "No HTTPS egress rules found for Lambda security group"
        fi
    else
        log_warning "VPN Lambda security group not found"
    fi
    
    # Find VPC endpoint security group
    local endpoint_sg_id
    endpoint_sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=*vpc-endpoint*" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
    
    if [[ -n "$endpoint_sg_id" && "$endpoint_sg_id" != "None" ]]; then
        log_success "VPC endpoint security group found: $endpoint_sg_id"
        
        # Check ingress rules
        local ingress_rules
        ingress_rules=$(aws ec2 describe-security-groups --group-ids "$endpoint_sg_id" \
            --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`tcp` && FromPort==`443`]' \
            --output json 2>/dev/null)
        
        if [[ "$ingress_rules" != "[]" && "$ingress_rules" != "null" ]]; then
            log_success "HTTPS ingress rules configured for VPC endpoint security group"
        else
            log_warning "No HTTPS ingress rules found for VPC endpoint security group"
        fi
    else
        log_warning "VPC endpoint security group not found"
    fi
}

# Function to run comprehensive connectivity tests
run_comprehensive_tests() {
    print_header "RUNNING COMPREHENSIVE CONNECTIVITY TESTS"
    
    if [[ "$COMPREHENSIVE" != "true" ]]; then
        log_info "Skipping comprehensive tests (use --comprehensive to enable)"
        return 0
    fi
    
    log_info "Running comprehensive connectivity tests..."
    
    # Test DNS resolution for VPC endpoints
    if [[ -n "$VPC_ID" ]]; then
        local region="${AWS_REGION:-us-gov-west-1}"
        local test_endpoints=(
            "bedrock-runtime.$region.amazonaws.com"
            "secretsmanager.$region.amazonaws.com"
            "logs.$region.amazonaws.com"
            "monitoring.$region.amazonaws.com"
        )
        
        log_info "Testing DNS resolution for AWS service endpoints..."
        
        for endpoint in "${test_endpoints[@]}"; do
            if nslookup "$endpoint" >/dev/null 2>&1; then
                log_success "DNS resolution successful: $endpoint"
            else
                log_warning "DNS resolution failed: $endpoint"
            fi
        done
    fi
    
    # Test network connectivity (if possible)
    log_info "Network connectivity tests would require Lambda function deployment"
    log_info "Consider running end-to-end tests after Lambda deployment"
}

# Function to generate validation report
generate_validation_report() {
    print_header "GENERATING VALIDATION REPORT"
    
    local report_file="$PROJECT_ROOT/outputs/vpn-connectivity-validation-report-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "VPN Connectivity Validation Report"
        echo "Generated: $(date)"
        echo "Project: $PROJECT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo ""
        echo "Validation Configuration:"
        echo "- AWS Region: ${AWS_REGION:-us-gov-west-1}"
        echo "- VPC ID: ${VPC_ID:-not provided}"
        echo "- VPN Connection ID: ${VPN_CONNECTION_ID:-not provided}"
        echo ""
        echo "Validation Results:"
        echo "- VPC Configuration: $(validate_vpc_configuration >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
        echo "- VPN Connection: $(validate_vpn_connection >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
        echo "- VPC Endpoints: $(validate_vpc_endpoints >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
        echo "- Security Groups: $(validate_security_groups >/dev/null 2>&1 && echo "PASS" || echo "FAIL")"
        echo ""
        echo "Recommendations:"
        echo "1. Ensure VPN tunnels are established and UP"
        echo "2. Verify all required VPC endpoints are available"
        echo "3. Test Lambda function deployment in VPC"
        echo "4. Run end-to-end connectivity tests"
        echo ""
        echo "Next Steps:"
        echo "1. Deploy VPN Lambda function if validation passes"
        echo "2. Run comprehensive connectivity tests"
        echo "3. Monitor VPN connection stability"
    } > "$report_file"
    
    log_success "Validation report generated: $report_file"
}

# Main execution function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--vpc-id)
                VPC_ID="$2"
                shift 2
                ;;
            -c|--vpn-connection-id)
                VPN_CONNECTION_ID="$2"
                shift 2
                ;;
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
            --stack-name)
                STACK_NAME="$2"
                shift 2
                ;;
            --comprehensive)
                COMPREHENSIVE="true"
                shift
                ;;
            --report-only)
                REPORT_ONLY="true"
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
    
    print_header "VPN CONNECTIVITY VALIDATION"
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "AWS Region: $AWS_REGION"
    
    # Execute validation steps
    validate_prerequisites
    
    # Get resources from CloudFormation stack if provided
    if [[ -n "$STACK_NAME" ]]; then
        get_stack_resources "$STACK_NAME"
    fi
    
    if [[ "$REPORT_ONLY" != "true" ]]; then
        validate_vpc_configuration
        validate_vpn_connection
        validate_vpc_endpoints
        validate_security_groups
        run_comprehensive_tests
    fi
    
    generate_validation_report
    
    print_header "VALIDATION COMPLETED"
    log_success "VPN connectivity validation completed"
    log_info "Review the validation report for detailed results"
    log_info "Proceed with Lambda deployment if all validations pass"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi