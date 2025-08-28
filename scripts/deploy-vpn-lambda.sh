#!/bin/bash

# Deployment script for VPN Lambda function
# Packages and deploys VPN Lambda function with VPC configuration, IAM roles, and environment variables

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LAMBDA_DIR="$PROJECT_ROOT/lambda"
INFRASTRUCTURE_DIR="$PROJECT_ROOT/infrastructure"

# Default configuration
PROJECT_NAME="dual-routing-api-gateway"
ENVIRONMENT="prod"
FUNCTION_NAME=""
STACK_NAME=""
TEMPLATE_FILE="$INFRASTRUCTURE_DIR/dual-routing-vpn-lambda.yaml"

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
    echo "Deploy VPN Lambda function with VPC configuration"
    echo ""
    echo "Options:"
    echo "  -e, --environment ENV         Environment (dev, stage, prod) [default: prod]"
    echo "  -p, --project-name NAME       Project name [default: dual-routing-api-gateway]"
    echo "  -f, --function-name NAME      Lambda function name [default: PROJECT_NAME-ENV-vpn-lambda]"
    echo "  -r, --region REGION           AWS region [default: us-gov-west-1]"
    echo "  --vpc-stack-name STACK        VPC infrastructure stack name"
    echo "  --commercial-secret SECRET    Commercial credentials secret name"
    echo "  --request-log-table TABLE     DynamoDB table for request logging"
    echo "  --memory-size MB              Lambda memory size in MB [default: 512]"
    echo "  --timeout SECONDS             Lambda timeout in seconds [default: 30]"
    echo "  --update-only                 Only update function code, don't recreate"
    echo "  --validate-only               Only validate template and package"
    echo "  --dry-run                     Show what would be deployed without executing"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --environment dev"
    echo "  $0 --environment prod --vpc-stack-name my-vpc-stack"
    echo "  $0 --update-only"
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
    
    # Check required files
    local required_files=(
        "$LAMBDA_DIR/dual_routing_vpn_lambda.py"
        "$LAMBDA_DIR/dual_routing_error_handler.py"
        "$TEMPLATE_FILE"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    log_success "All required files found"
    
    # Check Python for packaging
    if ! command_exists python3; then
        log_error "Python 3 not found. Required for Lambda packaging."
        exit 1
    fi
    
    log_success "Python 3 found: $(python3 --version)"
    
    # Check zip command
    if ! command_exists zip; then
        log_error "zip command not found. Required for Lambda packaging."
        exit 1
    fi
    
    log_success "zip command found"
}

# Function to get VPC infrastructure details
get_vpc_infrastructure_details() {
    print_header "RETRIEVING VPC INFRASTRUCTURE DETAILS"
    
    local vpc_stack_name="${VPC_STACK_NAME:-$PROJECT_NAME-$ENVIRONMENT-vpn-infrastructure}"
    
    log_info "Getting VPC details from CloudFormation stack: $vpc_stack_name"
    
    # Check if VPC stack exists
    if ! aws cloudformation describe-stacks --stack-name "$vpc_stack_name" >/dev/null 2>&1; then
        log_error "VPC infrastructure stack '$vpc_stack_name' not found"
        log_error "Please deploy VPC infrastructure first using deploy-vpn-infrastructure.sh"
        exit 1
    fi
    
    # Get stack outputs
    local outputs
    outputs=$(aws cloudformation describe-stacks --stack-name "$vpc_stack_name" --query 'Stacks[0].Outputs' --output json 2>/dev/null)
    
    if [[ "$outputs" != "null" && "$outputs" != "[]" ]]; then
        # Extract key values
        VPC_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPCId") | .OutputValue' 2>/dev/null || echo "")
        PRIVATE_SUBNET_1=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="PrivateSubnet1Id") | .OutputValue' 2>/dev/null || echo "")
        PRIVATE_SUBNET_2=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="PrivateSubnet2Id") | .OutputValue' 2>/dev/null || echo "")
        SECURITY_GROUP_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNLambdaSecurityGroupId") | .OutputValue' 2>/dev/null || echo "")
        BEDROCK_VPCE_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="BedrockVPCEndpointId") | .OutputValue' 2>/dev/null || echo "")
        SECRETS_VPCE_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="SecretsManagerVPCEndpointId") | .OutputValue' 2>/dev/null || echo "")
        DYNAMODB_VPCE_ID=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="DynamoDBVPCEndpointId") | .OutputValue' 2>/dev/null || echo "")
        
        log_success "Retrieved VPC infrastructure details:"
        log_info "  VPC ID: ${VPC_ID:-not found}"
        log_info "  Private Subnet 1: ${PRIVATE_SUBNET_1:-not found}"
        log_info "  Private Subnet 2: ${PRIVATE_SUBNET_2:-not found}"
        log_info "  Security Group: ${SECURITY_GROUP_ID:-not found}"
        log_info "  Bedrock VPC Endpoint: ${BEDROCK_VPCE_ID:-not found}"
        log_info "  Secrets Manager VPC Endpoint: ${SECRETS_VPCE_ID:-not found}"
        log_info "  DynamoDB VPC Endpoint: ${DYNAMODB_VPCE_ID:-not found}"
        
        # Validate required resources
        if [[ -z "$VPC_ID" || -z "$PRIVATE_SUBNET_1" || -z "$PRIVATE_SUBNET_2" || -z "$SECURITY_GROUP_ID" ]]; then
            log_error "Missing required VPC infrastructure resources"
            exit 1
        fi
        
        # Construct subnet IDs
        SUBNET_IDS="$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2"
        
        return 0
    else
        log_error "No outputs found in VPC infrastructure stack"
        exit 1
    fi
}

# Function to create Lambda deployment package
create_deployment_package() {
    print_header "CREATING LAMBDA DEPLOYMENT PACKAGE"
    
    local package_dir="$PROJECT_ROOT/build/vpn-lambda-package"
    local package_file="$PROJECT_ROOT/build/vpn-lambda-deployment.zip"
    
    # Create build directory
    mkdir -p "$package_dir"
    mkdir -p "$(dirname "$package_file")"
    
    log_info "Creating deployment package in: $package_dir"
    
    # Copy Lambda function files
    cp "$LAMBDA_DIR/dual_routing_vpn_lambda.py" "$package_dir/"
    cp "$LAMBDA_DIR/dual_routing_error_handler.py" "$package_dir/"
    
    log_success "Copied Lambda function files"
    
    # Install dependencies if requirements.txt exists
    if [[ -f "$LAMBDA_DIR/requirements.txt" ]]; then
        log_info "Installing Python dependencies..."
        
        # Install dependencies to package directory
        python3 -m pip install -r "$LAMBDA_DIR/requirements.txt" -t "$package_dir" --quiet
        
        log_success "Python dependencies installed"
    else
        log_info "No requirements.txt found, skipping dependency installation"
    fi
    
    # Create deployment package
    log_info "Creating deployment ZIP package..."
    
    cd "$package_dir"
    zip -r "$package_file" . -q
    cd "$PROJECT_ROOT"
    
    local package_size
    package_size=$(du -h "$package_file" | cut -f1)
    
    log_success "Deployment package created: $package_file ($package_size)"
    
    # Validate package size (Lambda limit is 50MB for direct upload)
    local package_size_bytes
    package_size_bytes=$(stat -f%z "$package_file" 2>/dev/null || stat -c%s "$package_file" 2>/dev/null)
    local max_size=$((50 * 1024 * 1024))  # 50MB
    
    if [[ $package_size_bytes -gt $max_size ]]; then
        log_warning "Package size ($package_size) exceeds 50MB. Consider using S3 for deployment."
        USE_S3_DEPLOYMENT="true"
    else
        log_info "Package size ($package_size) is within direct upload limits"
        USE_S3_DEPLOYMENT="false"
    fi
    
    DEPLOYMENT_PACKAGE="$package_file"
}

# Function to upload package to S3 if needed
upload_package_to_s3() {
    if [[ "$USE_S3_DEPLOYMENT" != "true" ]]; then
        return 0
    fi
    
    print_header "UPLOADING PACKAGE TO S3"
    
    local bucket_name="$PROJECT_NAME-$ENVIRONMENT-lambda-deployments"
    local s3_key="vpn-lambda/vpn-lambda-deployment-$(date +%Y%m%d_%H%M%S).zip"
    
    log_info "Uploading deployment package to S3..."
    
    # Create bucket if it doesn't exist
    if ! aws s3 ls "s3://$bucket_name" >/dev/null 2>&1; then
        log_info "Creating S3 bucket: $bucket_name"
        aws s3 mb "s3://$bucket_name" --region "${AWS_REGION:-us-gov-west-1}"
    fi
    
    # Upload package
    aws s3 cp "$DEPLOYMENT_PACKAGE" "s3://$bucket_name/$s3_key"
    
    S3_BUCKET="$bucket_name"
    S3_KEY="$s3_key"
    
    log_success "Package uploaded to S3: s3://$bucket_name/$s3_key"
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
}

# Function to check if Lambda function exists
lambda_function_exists() {
    aws lambda get-function --function-name "$1" >/dev/null 2>&1
}

# Function to deploy Lambda function
deploy_lambda_function() {
    print_header "DEPLOYING VPN LAMBDA FUNCTION"
    
    # Prepare parameters
    local parameters=(
        "ParameterKey=ProjectName,ParameterValue=$PROJECT_NAME"
        "ParameterKey=Environment,ParameterValue=$ENVIRONMENT"
        "ParameterKey=FunctionName,ParameterValue=$FUNCTION_NAME"
        "ParameterKey=VpcId,ParameterValue=$VPC_ID"
        "ParameterKey=SubnetIds,ParameterValue="$PRIVATE_SUBNET_1,$PRIVATE_SUBNET_2""
        "ParameterKey=SecurityGroupId,ParameterValue=$SECURITY_GROUP_ID"
        "ParameterKey=MemorySize,ParameterValue=${MEMORY_SIZE:-512}"
        "ParameterKey=Timeout,ParameterValue=${TIMEOUT:-30}"
    )
    
    # Add deployment package parameters
    if [[ "$USE_S3_DEPLOYMENT" == "true" ]]; then
        parameters+=("ParameterKey=S3Bucket,ParameterValue=$S3_BUCKET")
        parameters+=("ParameterKey=S3Key,ParameterValue=$S3_KEY")
    else
        # For direct upload, we'll update the function code separately
        parameters+=("ParameterKey=S3Bucket,ParameterValue=")
        parameters+=("ParameterKey=S3Key,ParameterValue=")
    fi
    
    # Add environment variable parameters
    if [[ -n "$COMMERCIAL_SECRET" ]]; then
        parameters+=("ParameterKey=CommercialCredentialsSecret,ParameterValue=$COMMERCIAL_SECRET")
    fi
    
    if [[ -n "$REQUEST_LOG_TABLE" ]]; then
        parameters+=("ParameterKey=RequestLogTable,ParameterValue=$REQUEST_LOG_TABLE")
    fi
    
    # Add VPC endpoint parameters
    if [[ -n "$BEDROCK_VPCE_ID" ]]; then
        parameters+=("ParameterKey=BedrockVpcEndpoint,ParameterValue=$BEDROCK_VPCE_ID")
    fi
    
    if [[ -n "$SECRETS_VPCE_ID" ]]; then
        parameters+=("ParameterKey=SecretsVpcEndpoint,ParameterValue=$SECRETS_VPCE_ID")
    fi
    
    if [[ -n "$DYNAMODB_VPCE_ID" ]]; then
        parameters+=("ParameterKey=DynamoDbVpcEndpoint,ParameterValue=$DYNAMODB_VPCE_ID")
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
    log_info "Function Name: $FUNCTION_NAME"
    log_info "Template: $TEMPLATE_FILE"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would deploy Lambda function with above configuration"
        return 0
    fi
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" >/dev/null 2>&1; then
        log_info "Updating existing Lambda function stack..."
        
        aws cloudformation update-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters $param_string \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM
        
        if wait_for_stack "$STACK_NAME" "update"; then
            log_success "Lambda function stack update completed"
        else
            log_error "Lambda function stack update failed"
            return 1
        fi
    else
        log_info "Creating new Lambda function stack..."
        
        aws cloudformation create-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters $param_string \
            --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
            --tags Key=Project,Value="$PROJECT_NAME" Key=Environment,Value="$ENVIRONMENT" Key=ManagedBy,Value=CloudFormation
        
        if wait_for_stack "$STACK_NAME" "creation"; then
            log_success "Lambda function stack creation completed"
        else
            log_error "Lambda function stack creation failed"
            return 1
        fi
    fi
    
    # Update function code if using direct upload
    if [[ "$USE_S3_DEPLOYMENT" != "true" ]]; then
        log_info "Updating Lambda function code..."
        
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --zip-file "fileb://$DEPLOYMENT_PACKAGE" >/dev/null
        
        log_success "Lambda function code updated"
    fi
}

# Function to wait for stack operation
wait_for_stack() {
    local stack_name="$1"
    local operation="$2"
    
    log_info "Waiting for stack $operation to complete..."
    
    local start_time=$(date +%s)
    local timeout=1800  # 30 minutes
    
    while true; do
        local status
        status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
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

# Function to test Lambda function
test_lambda_function() {
    print_header "TESTING VPN LAMBDA FUNCTION"
    
    log_info "Testing Lambda function deployment..."
    
    # Create test event
    local test_event='{
        "httpMethod": "GET",
        "path": "/v1/vpn/bedrock",
        "headers": {
            "Content-Type": "application/json"
        },
        "requestContext": {
            "identity": {
                "sourceIp": "10.0.1.100"
            }
        }
    }'
    
    # Invoke function
    local response
    response=$(aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload "$test_event" \
        --output json \
        /tmp/lambda-response.json 2>/dev/null)
    
    if [[ $? -eq 0 ]]; then
        local status_code
        status_code=$(echo "$response" | jq -r '.StatusCode' 2>/dev/null)
        
        if [[ "$status_code" == "200" ]]; then
            log_success "Lambda function test invocation successful"
            
            # Check response content
            if [[ -f "/tmp/lambda-response.json" ]]; then
                local response_body
                response_body=$(cat /tmp/lambda-response.json)
                
                if echo "$response_body" | jq -e '.statusCode' >/dev/null 2>&1; then
                    local http_status
                    http_status=$(echo "$response_body" | jq -r '.statusCode')
                    log_info "HTTP Status Code: $http_status"
                    
                    if [[ "$http_status" == "200" ]]; then
                        log_success "Lambda function is responding correctly"
                    else
                        log_warning "Lambda function returned HTTP status: $http_status"
                    fi
                fi
            fi
        else
            log_warning "Lambda function invocation returned status: $status_code"
        fi
    else
        log_warning "Lambda function test invocation failed"
        log_info "This may be normal if VPN connectivity is not yet established"
    fi
    
    # Clean up test file
    rm -f /tmp/lambda-response.json
}

# Function to display function details
display_function_details() {
    print_header "LAMBDA FUNCTION DETAILS"
    
    if ! lambda_function_exists "$FUNCTION_NAME"; then
        log_warning "Lambda function does not exist"
        return 1
    fi
    
    log_info "Retrieving Lambda function details..."
    
    local function_info
    function_info=$(aws lambda get-function --function-name "$FUNCTION_NAME" --output json 2>/dev/null)
    
    if [[ -n "$function_info" ]]; then
        local function_arn
        local runtime
        local memory_size
        local timeout
        local last_modified
        
        function_arn=$(echo "$function_info" | jq -r '.Configuration.FunctionArn' 2>/dev/null)
        runtime=$(echo "$function_info" | jq -r '.Configuration.Runtime' 2>/dev/null)
        memory_size=$(echo "$function_info" | jq -r '.Configuration.MemorySize' 2>/dev/null)
        timeout=$(echo "$function_info" | jq -r '.Configuration.Timeout' 2>/dev/null)
        last_modified=$(echo "$function_info" | jq -r '.Configuration.LastModified' 2>/dev/null)
        
        log_info "Function ARN: $function_arn"
        log_info "Runtime: $runtime"
        log_info "Memory Size: ${memory_size}MB"
        log_info "Timeout: ${timeout}s"
        log_info "Last Modified: $last_modified"
        
        # Check VPC configuration
        local vpc_config
        vpc_config=$(echo "$function_info" | jq -r '.Configuration.VpcConfig' 2>/dev/null)
        
        if [[ "$vpc_config" != "null" ]]; then
            local vpc_id
            local subnet_ids
            local security_group_ids
            
            vpc_id=$(echo "$vpc_config" | jq -r '.VpcId' 2>/dev/null)
            subnet_ids=$(echo "$vpc_config" | jq -r '.SubnetIds[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
            security_group_ids=$(echo "$vpc_config" | jq -r '.SecurityGroupIds[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
            
            log_info "VPC Configuration:"
            log_info "  VPC ID: $vpc_id"
            log_info "  Subnet IDs: $subnet_ids"
            log_info "  Security Group IDs: $security_group_ids"
        fi
    fi
}

# Function to generate deployment report
generate_deployment_report() {
    print_header "GENERATING DEPLOYMENT REPORT"
    
    local report_file="$PROJECT_ROOT/outputs/vpn-lambda-deployment-report-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "VPN Lambda Function Deployment Report"
        echo "Generated: $(date)"
        echo "Project: $PROJECT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo ""
        echo "Deployment Configuration:"
        echo "- Function Name: $FUNCTION_NAME"
        echo "- Stack Name: $STACK_NAME"
        echo "- AWS Region: ${AWS_REGION:-us-gov-west-1}"
        echo "- Memory Size: ${MEMORY_SIZE:-512}MB"
        echo "- Timeout: ${TIMEOUT:-30}s"
        echo ""
        echo "VPC Configuration:"
        echo "- VPC ID: ${VPC_ID:-not available}"
        echo "- Subnet IDs: ${SUBNET_IDS:-not available}"
        echo "- Security Group ID: ${SECURITY_GROUP_ID:-not available}"
        echo ""
        echo "VPC Endpoints:"
        echo "- Bedrock VPC Endpoint: ${BEDROCK_VPCE_ID:-not available}"
        echo "- Secrets Manager VPC Endpoint: ${SECRETS_VPCE_ID:-not available}"
        echo "- DynamoDB VPC Endpoint: ${DYNAMODB_VPCE_ID:-not available}"
        echo ""
        echo "Environment Variables:"
        echo "- Commercial Credentials Secret: ${COMMERCIAL_SECRET:-default}"
        echo "- Request Log Table: ${REQUEST_LOG_TABLE:-default}"
        echo ""
        echo "Deployment Package:"
        echo "- Package File: $DEPLOYMENT_PACKAGE"
        echo "- S3 Deployment: ${USE_S3_DEPLOYMENT:-false}"
        if [[ "$USE_S3_DEPLOYMENT" == "true" ]]; then
            echo "- S3 Bucket: ${S3_BUCKET:-not available}"
            echo "- S3 Key: ${S3_KEY:-not available}"
        fi
        echo ""
        echo "Next Steps:"
        echo "1. Test Lambda function with VPN connectivity"
        echo "2. Update API Gateway to integrate with VPN Lambda"
        echo "3. Run end-to-end tests"
        echo "4. Monitor function performance and VPC connectivity"
    } > "$report_file"
    
    log_success "Deployment report generated: $report_file"
}

# Main execution function
main() {
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
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -r|--region)
                export AWS_REGION="$2"
                shift 2
                ;;
            --vpc-stack-name)
                VPC_STACK_NAME="$2"
                shift 2
                ;;
            --commercial-secret)
                COMMERCIAL_SECRET="$2"
                shift 2
                ;;
            --request-log-table)
                REQUEST_LOG_TABLE="$2"
                shift 2
                ;;
            --memory-size)
                MEMORY_SIZE="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --update-only)
                UPDATE_ONLY="true"
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
    
    # Set defaults
    export AWS_REGION="${AWS_REGION:-us-gov-west-1}"
    FUNCTION_NAME="${FUNCTION_NAME:-$PROJECT_NAME-$ENVIRONMENT-vpn-lambda}"
    STACK_NAME="$PROJECT_NAME-$ENVIRONMENT-vpn-lambda"
    
    print_header "VPN LAMBDA FUNCTION DEPLOYMENT"
    log_info "Project: $PROJECT_NAME"
    log_info "Environment: $ENVIRONMENT"
    log_info "Function Name: $FUNCTION_NAME"
    log_info "AWS Region: $AWS_REGION"
    
    # Execute deployment steps
    validate_prerequisites
    get_vpc_infrastructure_details
    create_deployment_package
    upload_package_to_s3
    validate_template
    
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log_success "Validation completed successfully"
        exit 0
    fi
    
    if [[ "$UPDATE_ONLY" == "true" ]]; then
        log_info "Update-only mode: updating function code only"
        if lambda_function_exists "$FUNCTION_NAME"; then
            aws lambda update-function-code \
                --function-name "$FUNCTION_NAME" \
                --zip-file "fileb://$DEPLOYMENT_PACKAGE" >/dev/null
            log_success "Lambda function code updated"
        else
            log_error "Function $FUNCTION_NAME does not exist. Cannot update."
            exit 1
        fi
    else
        deploy_lambda_function
    fi
    
    test_lambda_function
    display_function_details
    generate_deployment_report
    
    print_header "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "VPN Lambda function has been deployed successfully"
    log_info "Function Name: $FUNCTION_NAME"
    log_info "Stack Name: $STACK_NAME"
    log_info "Next steps:"
    log_info "1. Update API Gateway with VPN Lambda integration"
    log_info "2. Run connectivity tests"
    log_info "3. Monitor function performance"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi