#!/bin/bash

# VPN Connectivity Test Runner
# This script runs comprehensive tests for the VPN connectivity solution

set -e

# Configuration
PROJECT_NAME="cross-partition-vpn"
ENVIRONMENT="test"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test types
TEST_TYPES=(
    "unit:Unit Tests"
    "integration:Integration Tests"
    "performance:Performance Tests"
    "security:Security Tests"
    "compliance:Compliance Tests"
)

echo -e "${GREEN}🧪 VPN Connectivity Test Suite${NC}"
echo -e "${BLUE}Project: $PROJECT_NAME${NC}"
echo -e "${BLUE}Environment: $ENVIRONMENT${NC}"
echo ""

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --type TYPE       Run specific test type (unit|integration|performance|security|compliance|all)"
    echo "  -e, --env ENV         Environment (dev|staging|prod) [default: test]"
    echo "  -v, --verbose         Verbose output"
    echo "  -r, --report          Generate detailed report"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Test Types:"
    for test_info in "${TEST_TYPES[@]}"; do
        IFS=':' read -r type desc <<< "$test_info"
        echo "  $type: $desc"
    done
    echo ""
}

# Parse command line arguments
TEST_TYPE="unit"
VERBOSE=false
GENERATE_REPORT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            TEST_TYPE="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -r|--report)
            GENERATE_REPORT=true
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
done

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}🔍 Checking test prerequisites${NC}"
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}❌ Python 3 not found${NC}"
        exit 1
    fi
    
    # Check required Python packages
    local required_packages=("boto3" "requests" "moto")
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" &> /dev/null; then
            echo -e "${YELLOW}⚠️  Installing missing package: $package${NC}"
            pip3 install "$package"
        fi
    done
    
    # Check test files
    if [ ! -f "../tests/test_vpn_connectivity.py" ]; then
        echo -e "${RED}❌ Test file not found: ../tests/test_vpn_connectivity.py${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Prerequisites check passed${NC}"
}

# Function to set up test environment
setup_test_environment() {
    echo -e "${YELLOW}🔧 Setting up test environment${NC}"
    
    # Set environment variables based on test type
    export TEST_ENV="$ENVIRONMENT"
    export PROJECT_NAME="$PROJECT_NAME"
    
    case $TEST_TYPE in
        "integration"|"all")
            export RUN_INTEGRATION_TESTS="true"
            # Get API endpoint from CloudFormation if available
            if command -v aws &> /dev/null; then
                local api_url=$(aws cloudformation describe-stacks \
                    --stack-name "${PROJECT_NAME}-govcloud-lambda" \
                    --profile $GOVCLOUD_PROFILE \
                    --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
                    --output text 2>/dev/null || echo "")
                
                if [ -n "$api_url" ]; then
                    export VPN_API_BASE_URL="$api_url"
                    echo "Using API URL: $api_url"
                fi
            fi
            ;;
        "performance"|"all")
            export RUN_PERFORMANCE_TESTS="true"
            ;;
        "security"|"all")
            export RUN_SECURITY_TESTS="true"
            ;;
    esac
    
    # Set Python path
    export PYTHONPATH="../:$PYTHONPATH"
    
    echo -e "${GREEN}✅ Test environment configured${NC}"
}

# Function to run unit tests
run_unit_tests() {
    echo -e "${BLUE}🔬 Running unit tests${NC}"
    
    cd ../tests
    python3 -m unittest test_vpn_connectivity.TestVPNConfiguration -v
    python3 -m unittest test_vpn_connectivity.TestVPCEndpointConnectivity -v
    python3 -m unittest test_vpn_connectivity.TestVPNTunnelFailover -v
    python3 -m unittest test_vpn_connectivity.TestComplianceValidation -v
    cd - > /dev/null
}

# Function to run integration tests
run_integration_tests() {
    echo -e "${BLUE}🔗 Running integration tests${NC}"
    
    if [ -z "$VPN_API_BASE_URL" ]; then
        echo -e "${YELLOW}⚠️  VPN_API_BASE_URL not set, skipping integration tests${NC}"
        return 0
    fi
    
    cd ../tests
    python3 -m unittest test_vpn_connectivity.TestCrossPartitionConnectivity -v
    cd - > /dev/null
}

# Function to run performance tests
run_performance_tests() {
    echo -e "${BLUE}⚡ Running performance tests${NC}"
    
    if [ -z "$VPN_API_BASE_URL" ]; then
        echo -e "${YELLOW}⚠️  VPN_API_BASE_URL not set, skipping performance tests${NC}"
        return 0
    fi
    
    cd ../tests
    python3 -m unittest test_vpn_connectivity.TestPerformanceBenchmarks -v
    cd - > /dev/null
}

# Function to run security tests
run_security_tests() {
    echo -e "${BLUE}🔒 Running security tests${NC}"
    
    cd ../tests
    python3 -m unittest test_vpn_connectivity.TestSecurityValidation -v
    cd - > /dev/null
}

# Function to run VPN connectivity validation
run_vpn_validation() {
    echo -e "${BLUE}🌐 Running VPN connectivity validation${NC}"
    
    if command -v aws &> /dev/null; then
        # Test VPN validation Lambda function
        local function_name="${PROJECT_NAME}-vpn-validation"
        
        if aws lambda get-function --function-name "$function_name" --profile $GOVCLOUD_PROFILE &>/dev/null; then
            echo "Invoking VPN validation function..."
            aws lambda invoke \
                --function-name "$function_name" \
                --profile $GOVCLOUD_PROFILE \
                --payload '{}' \
                --cli-binary-format raw-in-base64-out \
                /tmp/vpn-validation-result.json
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ VPN validation completed${NC}"
                if [ "$VERBOSE" = true ]; then
                    echo "Results:"
                    cat /tmp/vpn-validation-result.json | python3 -m json.tool
                fi
            else
                echo -e "${RED}❌ VPN validation failed${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  VPN validation function not found${NC}"
        fi
        
        # Test VPC endpoint connectivity
        local test_function_name="${PROJECT_NAME}-vpc-endpoint-test"
        
        if aws lambda get-function --function-name "$test_function_name" --profile $GOVCLOUD_PROFILE &>/dev/null; then
            echo "Testing VPC endpoint connectivity..."
            aws lambda invoke \
                --function-name "$test_function_name" \
                --profile $GOVCLOUD_PROFILE \
                --payload '{}' \
                --cli-binary-format raw-in-base64-out \
                /tmp/vpc-endpoint-test-result.json
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ VPC endpoint test completed${NC}"
                if [ "$VERBOSE" = true ]; then
                    echo "Results:"
                    cat /tmp/vpc-endpoint-test-result.json | python3 -m json.tool
                fi
            else
                echo -e "${RED}❌ VPC endpoint test failed${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  VPC endpoint test function not found${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  AWS CLI not available, skipping VPN validation${NC}"
    fi
}

# Function to generate test report
generate_test_report() {
    echo -e "${BLUE}📊 Generating test report${NC}"
    
    local report_file="/tmp/vpn-test-suite-report-$(date +%Y%m%d-%H%M%S).json"
    
    # Run complete test suite and capture results
    cd ../tests
    python3 test_vpn_connectivity.py > /tmp/test-output.log 2>&1
    local test_exit_code=$?
    cd - > /dev/null
    
    # Create comprehensive report
    cat > "$report_file" << EOF
{
    "test_suite": "VPN Connectivity",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "environment": "$ENVIRONMENT",
    "test_type": "$TEST_TYPE",
    "project": "$PROJECT_NAME",
    "exit_code": $test_exit_code,
    "success": $([ $test_exit_code -eq 0 ] && echo "true" || echo "false"),
    "test_output": "$(cat /tmp/test-output.log | sed 's/"/\\"/g' | tr '\n' ' ')",
    "files_tested": [
        "lambda/vpn_lambda_function.py",
        "lambda/vpc_endpoint_clients.py",
        "lambda/vpn_error_handling.py"
    ],
    "test_categories": {
        "unit_tests": "$([ "$TEST_TYPE" = "unit" ] || [ "$TEST_TYPE" = "all" ] && echo "executed" || echo "skipped")",
        "integration_tests": "$([ "$TEST_TYPE" = "integration" ] || [ "$TEST_TYPE" = "all" ] && echo "executed" || echo "skipped")",
        "performance_tests": "$([ "$TEST_TYPE" = "performance" ] || [ "$TEST_TYPE" = "all" ] && echo "executed" || echo "skipped")",
        "security_tests": "$([ "$TEST_TYPE" = "security" ] || [ "$TEST_TYPE" = "all" ] && echo "executed" || echo "skipped")"
    }
}
EOF
    
    echo -e "${GREEN}✅ Test report generated: $report_file${NC}"
    
    if [ "$VERBOSE" = true ]; then
        echo "Report contents:"
        cat "$report_file" | python3 -m json.tool
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Test Configuration:${NC}"
    echo "  Test Type: $TEST_TYPE"
    echo "  Environment: $ENVIRONMENT"
    echo "  Verbose: $VERBOSE"
    echo "  Generate Report: $GENERATE_REPORT"
    echo ""
    
    check_prerequisites
    setup_test_environment
    
    # Run tests based on type
    case $TEST_TYPE in
        "unit")
            run_unit_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "performance")
            run_performance_tests
            ;;
        "security")
            run_security_tests
            ;;
        "compliance")
            run_unit_tests
            run_vpn_validation
            ;;
        "all")
            run_unit_tests
            run_integration_tests
            run_performance_tests
            run_security_tests
            run_vpn_validation
            ;;
        *)
            echo -e "${RED}❌ Unknown test type: $TEST_TYPE${NC}"
            show_usage
            exit 1
            ;;
    esac
    
    # Generate report if requested
    if [ "$GENERATE_REPORT" = true ]; then
        generate_test_report
    fi
    
    echo -e "${GREEN}🎉 Test suite completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📋 Test Results Summary:${NC}"
    echo "• Unit tests validate core functionality"
    echo "• Integration tests verify end-to-end flows"
    echo "• Performance tests ensure latency requirements"
    echo "• Security tests validate encryption and isolation"
    echo "• VPN validation confirms tunnel connectivity"
    echo ""
    echo -e "${YELLOW}💡 Next Steps:${NC}"
    echo "1. Review test results and fix any failures"
    echo "2. Run performance tests under load"
    echo "3. Validate security controls in production"
    echo "4. Set up automated testing in CI/CD pipeline"
}

# Run main function
main "$@"