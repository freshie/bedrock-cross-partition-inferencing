#!/bin/bash

# Test execution script for API Gateway integration tests
# Validates dual routing path configuration and Lambda function integration

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TESTS_DIR="$PROJECT_ROOT/tests"
LAMBDA_DIR="$PROJECT_ROOT/lambda"

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to setup test environment
setup_test_environment() {
    print_header "SETTING UP INTEGRATION TEST ENVIRONMENT"
    
    # Check Python availability
    if command_exists python3; then
        PYTHON_CMD="python3"
        log_success "Python 3 found: $(python3 --version)"
    elif command_exists python; then
        PYTHON_CMD="python"
        log_success "Python found: $(python --version)"
    else
        log_error "Python not found. Please install Python 3.7 or higher."
        exit 1
    fi
    
    # Check if we're in the correct directory
    if [[ ! -d "$LAMBDA_DIR" ]]; then
        log_error "Lambda directory not found: $LAMBDA_DIR"
        log_error "Please run this script from the project root or scripts directory"
        exit 1
    fi
    
    if [[ ! -d "$TESTS_DIR" ]]; then
        log_error "Tests directory not found: $TESTS_DIR"
        exit 1
    fi
    
    # Check for required test files
    REQUIRED_FILES=(
        "$TESTS_DIR/test_api_gateway_integration.py"
        "$TESTS_DIR/run_api_gateway_integration_tests.py"
        "$LAMBDA_DIR/dual_routing_internet_lambda.py"
        "$LAMBDA_DIR/dual_routing_vpn_lambda.py"
        "$LAMBDA_DIR/dual_routing_error_handler.py"
    )
    
    for file in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    log_success "All required files found"
    
    # Create test results directory
    TEST_RESULTS_DIR="$TESTS_DIR/results"
    mkdir -p "$TEST_RESULTS_DIR"
    log_info "Test results directory: $TEST_RESULTS_DIR"
    
    # Set environment variables for testing
    export PYTHONPATH="$LAMBDA_DIR:$TESTS_DIR:$PYTHONPATH"
    export AWS_DEFAULT_REGION="us-gov-west-1"
    export AWS_REGION="us-gov-west-1"
    
    # Mock AWS credentials for testing (these won't be used in actual AWS calls during integration tests)
    export AWS_ACCESS_KEY_ID="test-access-key"
    export AWS_SECRET_ACCESS_KEY="test-secret-key"
    
    # Set test-specific environment variables
    export COMMERCIAL_CREDENTIALS_SECRET="test-commercial-creds"
    export REQUEST_LOG_TABLE="test-request-log-table"
    export VPC_ENDPOINT_BEDROCK="vpce-12345-bedrock"
    export VPC_ENDPOINT_SECRETS="vpce-12345-secrets"
    export VPC_ENDPOINT_DYNAMODB="vpce-12345-dynamodb"
    
    log_success "Integration test environment setup complete"
}

# Function to install test dependencies
install_dependencies() {
    print_header "INSTALLING INTEGRATION TEST DEPENDENCIES"
    
    # Check if requirements.txt exists
    if [[ -f "$TESTS_DIR/requirements.txt" ]]; then
        log_info "Installing test dependencies from requirements.txt..."
        
        # Try to install with pip
        if command_exists pip3; then
            pip3 install -r "$TESTS_DIR/requirements.txt" --quiet
        elif command_exists pip; then
            pip install -r "$TESTS_DIR/requirements.txt" --quiet
        else
            log_warning "pip not found. Attempting to continue without installing dependencies."
            log_warning "You may need to manually install: unittest, coverage, boto3, moto, requests"
            return
        fi
        
        log_success "Test dependencies installed successfully"
    else
        log_warning "requirements.txt not found in tests directory"
        log_info "Attempting to install common integration test dependencies..."
        
        # Try to install common dependencies
        if command_exists pip3; then
            pip3 install coverage boto3 moto requests --quiet 2>/dev/null || log_warning "Could not install some dependencies"
        elif command_exists pip; then
            pip install coverage boto3 moto requests --quiet 2>/dev/null || log_warning "Could not install some dependencies"
        fi
    fi
}

# Function to validate test files
validate_test_files() {
    print_header "VALIDATING INTEGRATION TEST FILES"
    
    # Check Python syntax
    log_info "Checking Python syntax for integration test files..."
    
    if $PYTHON_CMD -m py_compile "$TESTS_DIR/test_api_gateway_integration.py"; then
        log_success "test_api_gateway_integration.py syntax is valid"
    else
        log_error "Syntax error in test_api_gateway_integration.py"
        exit 1
    fi
    
    if $PYTHON_CMD -m py_compile "$TESTS_DIR/run_api_gateway_integration_tests.py"; then
        log_success "run_api_gateway_integration_tests.py syntax is valid"
    else
        log_error "Syntax error in run_api_gateway_integration_tests.py"
        exit 1
    fi
    
    # Check Lambda function syntax
    LAMBDA_FILES=(
        "dual_routing_internet_lambda.py"
        "dual_routing_vpn_lambda.py"
        "dual_routing_error_handler.py"
    )
    
    for lambda_file in "${LAMBDA_FILES[@]}"; do
        if $PYTHON_CMD -m py_compile "$LAMBDA_DIR/$lambda_file"; then
            log_success "$lambda_file syntax is valid"
        else
            log_error "Syntax error in $lambda_file"
            exit 1
        fi
    done
    
    log_success "All integration test files validated successfully"
}

# Function to run integration tests
run_integration_tests() {
    print_header "RUNNING API GATEWAY INTEGRATION TESTS"
    
    cd "$TESTS_DIR"
    
    # Run tests with custom runner
    log_info "Executing API Gateway integration tests with coverage analysis..."
    
    if $PYTHON_CMD run_api_gateway_integration_tests.py; then
        log_success "All API Gateway integration tests passed!"
        TEST_SUCCESS=true
    else
        log_error "Some API Gateway integration tests failed!"
        TEST_SUCCESS=false
    fi
    
    # Also run with standard unittest for additional verification
    print_separator
    log_info "Running additional verification with standard unittest..."
    
    if $PYTHON_CMD -m unittest test_api_gateway_integration -v; then
        log_success "Standard unittest verification passed"
    else
        log_warning "Standard unittest verification had issues"
    fi
    
    cd "$PROJECT_ROOT"
}

# Function to validate integration test results
validate_integration_results() {
    print_header "VALIDATING INTEGRATION TEST RESULTS"
    
    # Check if JSON results file was generated
    JSON_RESULTS="$TESTS_DIR/api_gateway_integration_test_results.json"
    if [[ -f "$JSON_RESULTS" ]]; then
        log_success "Integration test results JSON generated"
        
        # Extract key metrics from JSON
        if command_exists jq; then
            TOTAL_TESTS=$(jq -r '.test_run.total_tests' "$JSON_RESULTS")
            SUCCESS_RATE=$(jq -r '.test_run.success_rate' "$JSON_RESULTS")
            FAILED_TESTS=$(jq -r '.test_run.failed_tests' "$JSON_RESULTS")
            
            log_info "Integration Test Metrics:"
            log_info "- Total Tests: $TOTAL_TESTS"
            log_info "- Success Rate: ${SUCCESS_RATE}%"
            log_info "- Failed Tests: $FAILED_TESTS"
        else
            log_warning "jq not available for JSON parsing"
        fi
    else
        log_warning "Integration test results JSON not found"
    fi
    
    # Check for coverage reports
    if [[ -d "$TESTS_DIR/coverage_html_integration" ]]; then
        log_success "HTML coverage report generated for integration tests"
    else
        log_warning "HTML coverage report not generated"
    fi
}

# Function to generate integration test report
generate_integration_test_report() {
    print_header "GENERATING INTEGRATION TEST REPORT"
    
    REPORT_FILE="$TEST_RESULTS_DIR/api_gateway_integration_test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "API Gateway Dual Routing - Integration Test Report"
        echo "Generated: $(date)"
        echo "Project: Dual Routing API Gateway"
        echo "Component: API Gateway Integration"
        echo ""
        echo "Test Environment:"
        echo "- Python Version: $($PYTHON_CMD --version)"
        echo "- Test Directory: $TESTS_DIR"
        echo "- Lambda Directory: $LAMBDA_DIR"
        echo "- AWS Region: ${AWS_REGION:-us-gov-west-1}"
        echo ""
        echo "Test Results:"
        if [[ "$TEST_SUCCESS" == "true" ]]; then
            echo "- Status: PASSED ✓"
        else
            echo "- Status: FAILED ✗"
        fi
        echo ""
        echo "Components Tested:"
        echo "- dual_routing_internet_lambda.py"
        echo "- dual_routing_vpn_lambda.py"
        echo "- dual_routing_error_handler.py"
        echo ""
        echo "Integration Test Categories:"
        echo "- API Gateway path routing validation"
        echo "- Internet vs VPN Lambda routing detection"
        echo "- Authentication consistency across paths"
        echo "- GET request routing (models and info)"
        echo "- Request context preservation"
        echo "- Error response consistency"
        echo "- Response header validation"
        echo "- Path parameter extraction"
        echo "- Invalid path handling"
        echo "- Query parameter preservation"
        echo ""
        echo "Routing Paths Tested:"
        echo "- /v1/bedrock/invoke-model (Internet routing)"
        echo "- /v1/vpn/bedrock/invoke-model (VPN routing)"
        echo "- /v1/bedrock/models (Internet GET)"
        echo "- /v1/vpn/bedrock/models (VPN GET)"
        echo "- Various staged paths (/prod, /stage, /dev)"
        echo ""
        echo "Coverage Analysis:"
        if [[ -f "$TESTS_DIR/api_gateway_integration_test_results.json" ]]; then
            echo "- Detailed coverage data available in JSON report"
        else
            echo "- Coverage data not available"
        fi
        echo ""
        echo "Additional Files Generated:"
        if [[ -d "$TESTS_DIR/coverage_html_integration" ]]; then
            echo "- HTML Coverage Report: $TESTS_DIR/coverage_html_integration/index.html"
        fi
        if [[ -f "$TESTS_DIR/api_gateway_integration_test_results.json" ]]; then
            echo "- JSON Test Results: $TESTS_DIR/api_gateway_integration_test_results.json"
        fi
    } > "$REPORT_FILE"
    
    log_success "Integration test report generated: $REPORT_FILE"
}

# Function to cleanup test artifacts
cleanup_test_artifacts() {
    print_header "CLEANING UP INTEGRATION TEST ARTIFACTS"
    
    # Remove Python cache files
    find "$PROJECT_ROOT" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "*.pyc" -delete 2>/dev/null || true
    
    # Remove coverage files (but keep reports)
    rm -f "$TESTS_DIR/.coverage" 2>/dev/null || true
    
    log_success "Integration test artifacts cleaned up"
}

# Function to display final summary
display_final_summary() {
    print_header "API GATEWAY INTEGRATION TEST EXECUTION SUMMARY"
    
    echo "Integration Test Execution Details:"
    echo "- Component: API Gateway Dual Routing"
    echo "- Test Type: Integration Tests"
    echo "- Test Framework: Python unittest"
    echo "- Coverage Analysis: Enabled"
    echo "- Execution Time: $(date)"
    echo ""
    
    if [[ "$TEST_SUCCESS" == "true" ]]; then
        log_success "🎉 ALL API GATEWAY INTEGRATION TESTS PASSED!"
        echo ""
        echo "✓ API Gateway dual routing paths validated"
        echo "✓ Internet and VPN Lambda routing confirmed"
        echo "✓ Authentication consistency verified"
        echo "✓ Error handling uniformity validated"
        echo "✓ Request/response flow integrity confirmed"
        echo ""
        echo "The API Gateway dual routing system is properly configured and ready for deployment."
    else
        log_error "❌ SOME API GATEWAY INTEGRATION TESTS FAILED!"
        echo ""
        echo "Please review the test output above and fix any issues before proceeding."
        echo "Check the generated reports for detailed information about failures."
        echo ""
        echo "Common issues to check:"
        echo "- Lambda function routing logic"
        echo "- API Gateway path configuration"
        echo "- Authentication and authorization setup"
        echo "- Error handling consistency"
    fi
    
    echo ""
    echo "Next Steps:"
    if [[ "$TEST_SUCCESS" == "true" ]]; then
        echo "1. Review coverage reports to identify any gaps"
        echo "2. Run end-to-end tests with actual AWS services"
        echo "3. Deploy to test environment for live validation"
        echo "4. Execute load testing for both routing paths"
    else
        echo "1. Fix failing integration tests"
        echo "2. Verify Lambda function routing logic"
        echo "3. Check API Gateway path configuration"
        echo "4. Re-run this integration test suite"
    fi
    
    print_separator
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    print_header "API GATEWAY DUAL ROUTING - INTEGRATION TEST EXECUTION"
    log_info "Starting API Gateway integration test execution..."
    log_info "Project: Dual Routing API Gateway"
    log_info "Component: API Gateway Integration"
    
    # Execute test phases
    setup_test_environment
    install_dependencies
    validate_test_files
    run_integration_tests
    validate_integration_results
    generate_integration_test_report
    cleanup_test_artifacts
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    display_final_summary
    
    log_info "Total execution time: ${duration} seconds"
    
    # Exit with appropriate code
    if [[ "$TEST_SUCCESS" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi