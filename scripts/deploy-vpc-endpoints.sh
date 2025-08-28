#!/bin/bash

# Deployment script for VPC endpoints required for VPN Lambda operation
# Deploys VPC endpoints for Bedrock, Secrets Manager, DynamoDB, and CloudWatch

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
VPC_ID=""
SUBNET_IDS=""
SECURITY_GROUP_ID=""

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
    echo "Deploy VPC endpoints for VPN Lambda operation"
    echo ""
    echo "Options:"
    echo "  -v, --vpc-id VPC_ID           VPC ID where endpoints will be created"
    echo "  -s, --subnet-ids SUBNET_IDS   Comma-separated list of subnet IDs"
    echo "  -g, --security-group SG_ID    Security group ID for VPC endpoints"
    echo "  -e, --environment ENV         Environment (dev, stage, prod) [default: prod]"
    echo "  -p, --project-name NAME       Project name [default: dual-routing-api-gateway]"
    echo "  -r, --region REGION           AWS region [default: us-gov-west-1]"
    echo "  --dry-run                     Show what would be created without executing"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --vpc-id vpc-12345 --subnet-ids subnet-123,subnet-456 --security-group sg-789"
    echo "  $0 --environment dev --dry-run"
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
    
    log_success "AWS credentials validated"
    
    # Check required parameters
    if [[ -z "$VPC_ID" ]]; then
        log_error "VPC ID is required. Use --vpc-id option."
        exit 1
    fi
    
    if [[ -z "$SUBNET_IDS" ]]; then
        log_error "Subnet IDs are required. Use --subnet-ids option."
        exit 1
    fi
    
    if [[ -z "$SECURITY_GROUP_ID" ]]; then
        log_error "Security Group ID is required. Use --security-group option."
        exit 1
    fi
    
    # Validate VPC exists
    if ! aws ec2 describe-vpcs --vpc-ids "$VPC_ID" >/dev/null 2>&1; then
        log_error "VPC $VPC_ID not found or not accessible"
        exit 1
    fi
    
    log_success "VPC $VPC_ID validated"
    
    # Validate subnets
    IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
    for subnet in "${SUBNET_ARRAY[@]}"; do
        if ! aws ec2 describe-subnets --subnet-ids "$subnet" >/dev/null 2>&1; then
            log_error "Subnet $subnet not found or not accessible"
            exit 1
        fi
    done
    
    log_success "Subnets validated: $SUBNET_IDS"
    
    # Validate security group
    if ! aws ec2 describe-security-groups --group-ids "$SECURITY_GROUP_ID" >/dev/null 2>&1; then
        log_error "Security Group $SECURITY_GROUP_ID not found or not accessible"
        exit 1
    fi
    
    log_success "Security Group $SECURITY_GROUP_ID validated"
}

# Function to check if VPC endpoint exists
vpc_endpoint_exists() {
    local service_name="$1"
    aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=$service_name" \
        --query 'VpcEndpoints[0].VpcEndpointId' \
        --output text 2>/dev/null | grep -v "None" >/dev/null
}

# Function to create interface VPC endpoint
create_interface_endpoint() {
    local service_name="$1"
    local endpoint_name="$2"
    local policy_document="$3"
    
    log_info "Creating interface VPC endpoint for $service_name..."
    
    if vpc_endpoint_exists "$service_name"; then
        log_warning "VPC endpoint for $service_name already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create interface endpoint for $service_name"
        return 0
    fi
    
    # Convert subnet IDs to array format
    IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
    
    local create_cmd="aws ec2 create-vpc-endpoint"
    create_cmd="$create_cmd --vpc-id $VPC_ID"
    create_cmd="$create_cmd --service-name $service_name"
    create_cmd="$create_cmd --vpc-endpoint-type Interface"
    create_cmd="$create_cmd --subnet-ids ${SUBNET_ARRAY[*]}"
    create_cmd="$create_cmd --security-group-ids $SECURITY_GROUP_ID"
    create_cmd="$create_cmd --private-dns-enabled"
    
    if [[ -n "$policy_document" ]]; then
        create_cmd="$create_cmd --policy-document '$policy_document'"
    fi
    
    create_cmd="$create_cmd --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$endpoint_name},{Key=Project,Value=$PROJECT_NAME},{Key=Environment,Value=$ENVIRONMENT}]'"
    
    local endpoint_id
    endpoint_id=$(eval "$create_cmd" --query 'VpcEndpoint.VpcEndpointId' --output text)
    
    if [[ -n "$endpoint_id" && "$endpoint_id" != "None" ]]; then
        log_success "Created interface VPC endpoint: $endpoint_id"
        
        # Wait for endpoint to be available
        log_info "Waiting for endpoint to become available..."
        aws ec2 wait vpc-endpoint-available --vpc-endpoint-ids "$endpoint_id"
        log_success "VPC endpoint $endpoint_id is now available"
    else
        log_error "Failed to create VPC endpoint for $service_name"
        return 1
    fi
}

# Function to create gateway VPC endpoint
create_gateway_endpoint() {
    local service_name="$1"
    local endpoint_name="$2"
    local route_table_ids="$3"
    local policy_document="$4"
    
    log_info "Creating gateway VPC endpoint for $service_name..."
    
    if vpc_endpoint_exists "$service_name"; then
        log_warning "VPC endpoint for $service_name already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create gateway endpoint for $service_name"
        return 0
    fi
    
    # Convert route table IDs to array format
    IFS=',' read -ra RT_ARRAY <<< "$route_table_ids"
    
    local create_cmd="aws ec2 create-vpc-endpoint"
    create_cmd="$create_cmd --vpc-id $VPC_ID"
    create_cmd="$create_cmd --service-name $service_name"
    create_cmd="$create_cmd --vpc-endpoint-type Gateway"
    create_cmd="$create_cmd --route-table-ids ${RT_ARRAY[*]}"
    
    if [[ -n "$policy_document" ]]; then
        create_cmd="$create_cmd --policy-document '$policy_document'"
    fi
    
    create_cmd="$create_cmd --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=$endpoint_name},{Key=Project,Value=$PROJECT_NAME},{Key=Environment,Value=$ENVIRONMENT}]'"
    
    local endpoint_id
    endpoint_id=$(eval "$create_cmd" --query 'VpcEndpoint.VpcEndpointId' --output text)
    
    if [[ -n "$endpoint_id" && "$endpoint_id" != "None" ]]; then
        log_success "Created gateway VPC endpoint: $endpoint_id"
    else
        log_error "Failed to create VPC endpoint for $service_name"
        return 1
    fi
}

# Function to get route table IDs for private subnets
get_private_route_tables() {
    local route_tables=""
    
    IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNET_IDS"
    for subnet in "${SUBNET_ARRAY[@]}"; do
        local rt_id
        rt_id=$(aws ec2 describe-route-tables \
            --filters "Name=association.subnet-id,Values=$subnet" \
            --query 'RouteTables[0].RouteTableId' \
            --output text 2>/dev/null)
        
        if [[ -n "$rt_id" && "$rt_id" != "None" ]]; then
            if [[ -n "$route_tables" ]]; then
                route_tables="$route_tables,$rt_id"
            else
                route_tables="$rt_id"
            fi
        fi
    done
    
    echo "$route_tables"
}

# Function to deploy VPC endpoints
deploy_vpc_endpoints() {
    print_header "DEPLOYING VPC ENDPOINTS"
    
    local region="${AWS_REGION:-us-gov-west-1}"
    
    # Bedrock Runtime VPC Endpoint (Interface)
    local bedrock_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": "*",
                "Action": [
                    "bedrock:InvokeModel",
                    "bedrock:InvokeModelWithResponseStream",
                    "bedrock:ListFoundationModels",
                    "bedrock:GetFoundationModel"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    create_interface_endpoint \
        "com.amazonaws.$region.bedrock-runtime" \
        "$PROJECT_NAME-$ENVIRONMENT-bedrock-vpce" \
        "$bedrock_policy"
    
    # Secrets Manager VPC Endpoint (Interface)
    local secrets_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": "*",
                "Action": [
                    "secretsmanager:GetSecretValue",
                    "secretsmanager:DescribeSecret"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    create_interface_endpoint \
        "com.amazonaws.$region.secretsmanager" \
        "$PROJECT_NAME-$ENVIRONMENT-secrets-vpce" \
        "$secrets_policy"
    
    # CloudWatch Logs VPC Endpoint (Interface)
    local logs_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": "*",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    create_interface_endpoint \
        "com.amazonaws.$region.logs" \
        "$PROJECT_NAME-$ENVIRONMENT-logs-vpce" \
        "$logs_policy"
    
    # CloudWatch VPC Endpoint (Interface)
    local cloudwatch_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": "*",
                "Action": [
                    "cloudwatch:PutMetricData",
                    "cloudwatch:GetMetricStatistics",
                    "cloudwatch:ListMetrics"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    create_interface_endpoint \
        "com.amazonaws.$region.monitoring" \
        "$PROJECT_NAME-$ENVIRONMENT-cloudwatch-vpce" \
        "$cloudwatch_policy"
    
    # DynamoDB VPC Endpoint (Gateway)
    local route_tables
    route_tables=$(get_private_route_tables)
    
    if [[ -n "$route_tables" ]]; then
        local dynamodb_policy='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": [
                        "dynamodb:PutItem",
                        "dynamodb:GetItem",
                        "dynamodb:UpdateItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:Query",
                        "dynamodb:Scan"
                    ],
                    "Resource": "*"
                }
            ]
        }'
        
        create_gateway_endpoint \
            "com.amazonaws.$region.dynamodb" \
            "$PROJECT_NAME-$ENVIRONMENT-dynamodb-vpce" \
            "$route_tables" \
            "$dynamodb_policy"
    else
        log_warning "No route tables found for DynamoDB gateway endpoint"
    fi
}

# Function to validate VPC endpoints
validate_vpc_endpoints() {
    print_header "VALIDATING VPC ENDPOINTS"
    
    local region="${AWS_REGION:-us-gov-west-1}"
    local endpoints=(
        "com.amazonaws.$region.bedrock-runtime"
        "com.amazonaws.$region.secretsmanager"
        "com.amazonaws.$region.logs"
        "com.amazonaws.$region.monitoring"
        "com.amazonaws.$region.dynamodb"
    )
    
    local created_count=0
    local total_count=${#endpoints[@]}
    
    for service in "${endpoints[@]}"; do
        if vpc_endpoint_exists "$service"; then
            log_success "VPC endpoint exists for $service"
            ((created_count++))
        else
            log_warning "VPC endpoint missing for $service"
        fi
    done
    
    log_info "VPC endpoints created: $created_count/$total_count"
    
    if [[ $created_count -eq $total_count ]]; then
        log_success "All required VPC endpoints are available"
    else
        log_warning "Some VPC endpoints are missing"
    fi
}

# Function to list VPC endpoints
list_vpc_endpoints() {
    print_header "VPC ENDPOINTS SUMMARY"
    
    log_info "Listing VPC endpoints in VPC: $VPC_ID"
    
    local endpoints
    endpoints=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'VpcEndpoints[*].[VpcEndpointId,ServiceName,State,VpcEndpointType]' \
        --output table 2>/dev/null)
    
    if [[ -n "$endpoints" ]]; then
        echo "$endpoints"
    else
        log_warning "No VPC endpoints found in VPC $VPC_ID"
    fi
}

# Function to generate deployment report
generate_deployment_report() {
    print_header "GENERATING DEPLOYMENT REPORT"
    
    local report_file="$PROJECT_ROOT/outputs/vpc-endpoints-deployment-report-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "VPC Endpoints Deployment Report"
        echo "Generated: $(date)"
        echo "Project: $PROJECT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo ""
        echo "Deployment Configuration:"
        echo "- VPC ID: $VPC_ID"
        echo "- Subnet IDs: $SUBNET_IDS"
        echo "- Security Group ID: $SECURITY_GROUP_ID"
        echo "- AWS Region: ${AWS_REGION:-us-gov-west-1}"
        echo ""
        echo "VPC Endpoints Created:"
        echo "- Bedrock Runtime (Interface)"
        echo "- Secrets Manager (Interface)"
        echo "- CloudWatch Logs (Interface)"
        echo "- CloudWatch Monitoring (Interface)"
        echo "- DynamoDB (Gateway)"
        echo ""
        echo "Next Steps:"
        echo "1. Test VPC endpoint connectivity from Lambda functions"
        echo "2. Deploy VPN Lambda function"
        echo "3. Run end-to-end connectivity tests"
    } > "$report_file"
    
    log_success "Deployment report generated: $report_file"
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
            -s|--subnet-ids)
                SUBNET_IDS="$2"
                shift 2
                ;;
            -g|--security-group)
                SECURITY_GROUP_ID="$2"
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
    
    print_header "VPC ENDPOINTS DEPLOYMENT"
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "VPC ID: $VPC_ID"
    log_info "AWS Region: $AWS_REGION"
    
    # Execute deployment steps
    validate_prerequisites
    deploy_vpc_endpoints
    validate_vpc_endpoints
    list_vpc_endpoints
    generate_deployment_report
    
    print_header "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "VPC endpoints have been deployed successfully"
    log_info "VPC ID: $VPC_ID"
    log_info "All required AWS service endpoints are now available in the VPC"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi