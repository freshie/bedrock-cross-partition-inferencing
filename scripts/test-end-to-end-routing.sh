#!/bin/bash

# Test execution script for end-to-end dual routing tests
# Validates complete flow from API Gateway through Lambda functions to Bedrock

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
    print_header "SETTING UP END-TO-END TEST ENVIRONMENT"
    
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
        "$TESTS_DIR/test_end_to_end_routing.py"
        "$TESTS_DIR/run_end_to_end_tests.py"
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
    
    # Mock AWS credentials for testing (these won't be used in actual AWS calls during end-to-end tests)
    export AWS_ACCESS_KEY_ID="test-access-key"
    export AWS_SECRET_ACCESS_KEY="test-secret-key"
    
    # Set test-specific environment variables
    export COMMERCIAL_CREDENTIALS_SECRET="test-commercial-creds"
    export REQUEST_LOG_TABLE="test-request-log-table"
    export VPC_ENDPOINT_BEDROCK="vpce-12345-bedrock"
    export VPC_ENDPOINT_SECRETS="vpce-12345-secrets"
    export VPC_ENDPOINT_DYNAMODB="vpce-12345-dynamodb"
    
    log_success "End-to-end test environment setup complete"
}

# Function to install test dependencies
install_dependencies() {
    print_header "INSTALLING END-TO-END TEST DEPENDENCIES"
    
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
        log_info "Attempting to install common end-to-end test dependencies..."
        
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
    print_header "VALIDATING END-TO-END TEST FILES"
    
    # Check Python syntax
    log_info "Checking Python syntax for end-to-end test files..."
    
    if $PYTHON_CMD -m py_compile "$TESTS_DIR/test_end_to_end_routing.py"; then
        log_success "test_end_to_end_routing.py syntax is valid"
    else
        log_error "Syntax error in test_end_to_end_routing.py"
        exit 1
    fi
    
    if $PYTHON_CMD -m py_compile "$TESTS_DIR/run_end_to_end_tests.py"; then
        log_success "run_end_to_end_tests.py syntax is valid"
    else
        log_error "Syntax error in run_end_to_end_tests.py"
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
    
    log_success "All end-to-end test files validated successfully"
}

# Function to run prerequisite tests
run_prerequisite_tests() {
    print_header "RUNNING PREREQUISITE TESTS"
    
    log_info "Checking if unit tests pass before running end-to-end tests..."
    
    # Run unit tests for both Lambda functions
    UNIT_TEST_SCRIPTS=(
        "$SCRIPT_DIR/test-internet-lambda-unit.sh"
        "$SCRIPT_DIR/test-vpn-lambda-unit.sh"
    )
    
    for script in "${UNIT_TEST_SCRIPTS[@]}"; do
        if [[ -f "$script" ]]; then
            script_name=$(basename "$script")
            log_info "Running prerequisite test: $script_name"
            
            if bash "$script" > /dev/null 2>&1; then
                log_success "$script_name passed"
            else
                log_warning "$script_name failed - continuing with end-to-end tests anyway"
            fi
        else
            log_warning "Prerequisite test script not found: $script"
        fi
    done
    
    log_success "Prerequisite test check complete"
}

# Function to run end-to-end tests
run_end_to_end_tests() {
    print_header "RUNNING END-TO-END DUAL ROUTING TESTS"
    
    cd "$TESTS_DIR"
    
    # Run tests with custom runner
    log_info "Executing end-to-end dual routing tests with coverage analysis..."
    
    if $PYTHON_CMD run_end_to_end_tests.py; then
        log_success "All end-to-end dual routing tests passed!"
        TEST_SUCCESS=true
    else
        log_error "Some end-to-end dual routing tests failed!"
        TEST_SUCCESS=false
    fi
    
    # Also run with standard unittest for additional verification
    print_separator
    log_info "Running additional verification with standard unittest..."
    
    if $PYTHON_CMD -m unittest test_end_to_end_routing -v; then
        log_success "Standard unittest verification passed"
    else
        log_warning "Standard unittest verification had issues"
    fi
    
    cd "$PROJECT_ROOT"
}

# Function to validate end-to-end test results
validate_end_to_end_results() {
    print_header "VALIDATING END-TO-END TEST RESULTS"
    
    # Check if JSON results file was generated
    JSON_RESULTS="$TESTS_DIR/end_to_end_test_results.json"
    if [[ -f "$JSON_RESULTS" ]]; then
        log_success "End-to-end test results JSON generated"
        
        # Extract key metrics from JSON
        if command_exists jq; then
            TOTAL_TESTS=$(jq -r '.test_run.total_tests' "$JSON_RESULTS")
            SUCCESS_RATE=$(jq -r '.test_run.success_rate' "$JSON_RESULTS")
            FAILED_TESTS=$(jq -r '.test_run.failed_tests' "$JSON_RESULTS")
            INTERNET_LATENCY=$(jq -r '.performance_metrics.internet_routing_latency' "$JSON_RESULTS")
            VPN_LATENCY=$(jq -r '.performance_metrics.vpn_routing_latency' "$JSON_RESULTS")
            
            log_info "End-to-End Test Metrics:"
            log_info "- Total Tests: $TOTAL_TESTS"
            log_info "- Success Rate: ${SUCCESS_RATE}%"
            log_info "- Failed Tests: $FAILED_TESTS"
            
            if [[ "$INTERNET_LATENCY" != "null" && "$VPN_LATENCY" != "null" ]]; then
                log_info "- Internet Routing Latency: ${INTERNET_LATENCY}ms"
                log_info "- VPN Routing Latency: ${VPN_LATENCY}ms"
            fi
        else
            log_warning "jq not available for JSON parsing"
        fi
    else
        log_warning "End-to-end test results JSON not found"
    fi
    
    # Check for coverage reports
    if [[ -d "$TESTS_DIR/coverage_html_e2e" ]]; then
        log_success "HTML coverage report generated for end-to-end tests"
    else
        log_warning "HTML coverage report not generated"
    fi
}

# Function to generate end-to-end test report
generate_end_to_end_test_report() {
    print_header "GENERATING END-TO-END TEST REPORT"
    
    REPORT_FILE="$TEST_RESULTS_DIR/end_to_end_test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Dual Routing System - End-to-End Test Report"
        echo "Generated: $(date)"
        echo "Project: Dual Routing API Gateway"
        echo "Component: End-to-End System Validation"
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
        echo "- dual_routing_internet_lambda.py (Complete flow)"
        echo "- dual_routing_vpn_lambda.py (Complete flow)"
        echo "- dual_routing_error_handler.py (Error scenarios)"
        echo ""
        echo "End-to-End Test Categories:"
        echo "- Complete internet routing flow validation"
        echo "- Complete VPN routing flow validation"
        echo "- Authentication and error handling end-to-end"
        echo "- Network failure scenarios"
        echo "- VPC endpoint connectivity testing"
        echo "- Functional equivalence comparison"
        echo "- Performance comparison between routing methods"
        echo "- Error handling consistency validation"
        echo ""
        echo "Test Scenarios Covered:"
        echo "- API Gateway → Internet Lambda → Commercial Bedrock (API Key)"
        echo "- API Gateway → Internet Lambda → Commercial Bedrock (AWS Credentials)"
        echo "- API Gateway → VPN Lambda → Commercial Bedrock (via VPC)"
        echo "- Authentication failures (both routing methods)"
        echo "- Network connectivity failures"
        echo "- VPC endpoint failures"
        echo "- Functional equivalence validation"
        echo "- Performance comparison analysis"
        echo ""
        echo "Coverage Analysis:"
        if [[ -f "$TESTS_DIR/end_to_end_test_results.json" ]]; then
            echo "- Detailed coverage data available in JSON report"
        else
            echo "- Coverage data not available"
        fi
        echo ""
        echo "Additional Files Generated:"
        if [[ -d "$TESTS_DIR/coverage_html_e2e" ]]; then
            echo "- HTML Coverage Report: $TESTS_DIR/coverage_html_e2e/index.html"
        fi
        if [[ -f "$TESTS_DIR/end_to_end_test_results.json" ]]; then
            echo "- JSON Test Results: $TESTS_DIR/end_to_end_test_results.json"
        fi
    } > "$REPORT_FILE"
    
    log_success "End-to-end test report generated: $REPORT_FILE"
}

# Function to cleanup test artifacts
cleanup_test_artifacts() {
    print_header "CLEANING UP END-TO-END TEST ARTIFACTS"
    
    # Remove Python cache files
    find "$PROJECT_ROOT" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "*.pyc" -delete 2>/dev/null || true
    
    # Remove coverage files (but keep reports)
    rm -f "$TESTS_DIR/.coverage" 2>/dev/null || true
    
    log_success "End-to-end test artifacts cleaned up"
}

# Function to display final summary
display_final_summary() {
    print_header "END-TO-END DUAL ROUTING TEST EXECUTION SUMMARY"
    
    echo "End-to-End Test Execution Details:"
    echo "- Component: Dual Routing System"
    echo "- Test Type: End-to-End Tests"
    echo "- Test Framework: Python unittest"
    echo "- Coverage Analysis: Enabled"
    echo "- Execution Time: $(date)"
    echo ""
    
    if [[ "$TEST_SUCCESS" == "true" ]]; then
        log_success "🎉 ALL END-TO-END TESTS PASSED!"
        echo ""
        echo "✓ Complete internet routing flow validated"
        echo "✓ Complete VPN routing flow validated"
        echo "✓ Functional equivalence between routing methods confirmed"
        echo "✓ Error handling consistency verified"
        echo "✓ Performance characteristics measured"
        echo "✓ Authentication and authorization end-to-end validated"
        echo "✓ Network failure scenarios tested"
        echo ""
        echo "The dual routing system is fully functional and ready for production deployment."
        echo "Both internet and VPN routing methods work correctly and provide equivalent functionality."
    else
        log_error "❌ SOME END-TO-END TESTS FAILED!"
        echo ""
        echo "Please review the test output above and fix any issues before proceeding."
        echo "Check the generated reports for detailed information about failures."
        echo ""
        echo "Common issues to investigate:"
        echo "- Lambda function integration problems"
        echo "- Bedrock API connectivity issues"
        echo "- VPC endpoint configuration problems"
        echo "- Authentication and authorization failures"
        echo "- Network connectivity issues"
        echo "- Performance degradation"
    fi
    
    echo ""
    echo "Next Steps:"
    if [[ "$TEST_SUCCESS" == "true" ]]; then
        echo "1. Review performance metrics and optimize if needed"
        echo "2. Deploy to staging environment for live testing"
        echo "3. Run load testing for both routing paths"
        echo "4. Set up monitoring and alerting"
        echo "5. Prepare for production deployment"
    else
        echo "1. Fix failing end-to-end tests"
        echo "2. Verify Lambda function implementations"
        echo "3. Check AWS service integrations"
        echo "4. Validate network connectivity"
        echo "5. Re-run this end-to-end test suite"
    fi
    
    print_separator
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    print_header "DUAL ROUTING SYSTEM - END-TO-END TEST EXECUTION"
    log_info "Starting end-to-end dual routing test execution..."
    log_info "Project: Dual Routing API Gateway"
    log_info "Component: End-to-End System Validation"
    
    # Execute test phases
    setup_test_environment
    install_dependencies
    validate_test_files
    run_prerequisite_tests
    run_end_to_end_tests
    validate_end_to_end_results
    generate_end_to_end_test_report
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