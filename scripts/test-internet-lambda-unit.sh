#!/bin/bash

# Test execution script for Internet Lambda function unit tests
# Provides comprehensive test execution with environment setup and validation

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
    print_header "SETTING UP TEST ENVIRONMENT"
    
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
        "$TESTS_DIR/test_internet_lambda_unit.py"
        "$TESTS_DIR/run_internet_lambda_tests.py"
        "$LAMBDA_DIR/dual_routing_internet_lambda.py"
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
    
    # Mock AWS credentials for testing (these won't be used in actual AWS calls during unit tests)
    export AWS_ACCESS_KEY_ID="test-access-key"
    export AWS_SECRET_ACCESS_KEY="test-secret-key"
    
    log_success "Test environment setup complete"
}

# Function to install test dependencies
install_dependencies() {
    print_header "INSTALLING TEST DEPENDENCIES"
    
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
            log_warning "You may need to manually install: unittest, coverage, boto3, moto"
            return
        fi
        
        log_success "Test dependencies installed successfully"
    else
        log_warning "requirements.txt not found in tests directory"
        log_info "Attempting to install common test dependencies..."
        
        # Try to install common dependencies
        if command_exists pip3; then
            pip3 install coverage boto3 moto --quiet 2>/dev/null || log_warning "Could not install some dependencies"
        elif command_exists pip; then
            pip install coverage boto3 moto --quiet 2>/dev/null || log_warning "Could not install some dependencies"
        fi
    fi
}

# Function to validate test files
validate_test_files() {
    print_header "VALIDATING TEST FILES"
    
    # Check Python syntax
    log_info "Checking Python syntax for test files..."
    
    if $PYTHON_CMD -m py_compile "$TESTS_DIR/test_internet_lambda_unit.py"; then
        log_success "test_internet_lambda_unit.py syntax is valid"
    else
        log_error "Syntax error in test_internet_lambda_unit.py"
        exit 1
    fi
    
    if $PYTHON_CMD -m py_compile "$TESTS_DIR/run_internet_lambda_tests.py"; then
        log_success "run_internet_lambda_tests.py syntax is valid"
    else
        log_error "Syntax error in run_internet_lambda_tests.py"
        exit 1
    fi
    
    # Check Lambda function syntax
    if $PYTHON_CMD -m py_compile "$LAMBDA_DIR/dual_routing_internet_lambda.py"; then
        log_success "dual_routing_internet_lambda.py syntax is valid"
    else
        log_error "Syntax error in dual_routing_internet_lambda.py"
        exit 1
    fi
    
    log_success "All test files validated successfully"
}

# Function to run unit tests
run_unit_tests() {
    print_header "RUNNING INTERNET LAMBDA UNIT TESTS"
    
    cd "$TESTS_DIR"
    
    # Run tests with custom runner
    log_info "Executing Internet Lambda unit tests with coverage analysis..."
    
    if $PYTHON_CMD run_internet_lambda_tests.py; then
        log_success "All Internet Lambda unit tests passed!"
        TEST_SUCCESS=true
    else
        log_error "Some Internet Lambda unit tests failed!"
        TEST_SUCCESS=false
    fi
    
    # Also run with standard unittest for additional verification
    print_separator
    log_info "Running additional verification with standard unittest..."
    
    if $PYTHON_CMD -m unittest test_internet_lambda_unit -v; then
        log_success "Standard unittest verification passed"
    else
        log_warning "Standard unittest verification had issues"
    fi
    
    cd "$PROJECT_ROOT"
}

# Function to generate test report
generate_test_report() {
    print_header "GENERATING TEST REPORT"
    
    REPORT_FILE="$TEST_RESULTS_DIR/internet_lambda_test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Internet Lambda Function - Unit Test Report"
        echo "Generated: $(date)"
        echo "Project: Dual Routing API Gateway"
        echo "Component: Internet Lambda Function"
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
        echo "Files Tested:"
        echo "- dual_routing_internet_lambda.py"
        echo "- dual_routing_error_handler.py (imported)"
        echo ""
        echo "Test Categories:"
        echo "- Basic functionality tests"
        echo "- Routing method detection"
        echo "- Request parsing and validation"
        echo "- Commercial credentials handling"
        echo "- Bedrock forwarding (API key and AWS credentials)"
        echo "- Error handling and recovery"
        echo "- Logging and metrics"
        echo "- GET request handling (models and routing info)"
        echo "- Advanced features (inference profiles, base64 decoding)"
        echo ""
        echo "Coverage Analysis:"
        if [[ -f "$TESTS_DIR/internet_lambda_test_results.json" ]]; then
            echo "- Detailed coverage data available in JSON report"
        else
            echo "- Coverage data not available"
        fi
        echo ""
        echo "Additional Files Generated:"
        if [[ -d "$TESTS_DIR/coverage_html_internet" ]]; then
            echo "- HTML Coverage Report: $TESTS_DIR/coverage_html_internet/index.html"
        fi
        if [[ -f "$TESTS_DIR/internet_lambda_test_results.json" ]]; then
            echo "- JSON Test Results: $TESTS_DIR/internet_lambda_test_results.json"
        fi
    } > "$REPORT_FILE"
    
    log_success "Test report generated: $REPORT_FILE"
}

# Function to cleanup test artifacts
cleanup_test_artifacts() {
    print_header "CLEANING UP TEST ARTIFACTS"
    
    # Remove Python cache files
    find "$PROJECT_ROOT" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$PROJECT_ROOT" -name "*.pyc" -delete 2>/dev/null || true
    
    # Remove coverage files (but keep reports)
    rm -f "$TESTS_DIR/.coverage" 2>/dev/null || true
    
    log_success "Test artifacts cleaned up"
}

# Function to display final summary
display_final_summary() {
    print_header "INTERNET LAMBDA UNIT TEST EXECUTION SUMMARY"
    
    echo "Test Execution Details:"
    echo "- Component: Internet Lambda Function"
    echo "- Test Type: Unit Tests"
    echo "- Test Framework: Python unittest"
    echo "- Coverage Analysis: Enabled"
    echo "- Execution Time: $(date)"
    echo ""
    
    if [[ "$TEST_SUCCESS" == "true" ]]; then
        log_success "🎉 ALL INTERNET LAMBDA UNIT TESTS PASSED!"
        echo ""
        echo "✓ Internet routing functionality validated"
        echo "✓ Error handling mechanisms tested"
        echo "✓ Commercial Bedrock integration verified"
        echo "✓ Dual routing architecture compliance confirmed"
        echo ""
        echo "The Internet Lambda function is ready for deployment and integration testing."
    else
        log_error "❌ SOME INTERNET LAMBDA UNIT TESTS FAILED!"
        echo ""
        echo "Please review the test output above and fix any issues before proceeding."
        echo "Check the generated reports for detailed information about failures."
    fi
    
    echo ""
    echo "Next Steps:"
    if [[ "$TEST_SUCCESS" == "true" ]]; then
        echo "1. Review coverage reports to identify any gaps"
        echo "2. Run integration tests with VPN Lambda function"
        echo "3. Deploy to test environment for end-to-end validation"
        echo "4. Execute dual routing system tests"
    else
        echo "1. Fix failing unit tests"
        echo "2. Re-run this test suite"
        echo "3. Ensure all tests pass before proceeding"
    fi
    
    print_separator
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    print_header "INTERNET LAMBDA FUNCTION - UNIT TEST EXECUTION"
    log_info "Starting Internet Lambda unit test execution..."
    log_info "Project: Dual Routing API Gateway"
    log_info "Component: Internet Lambda Function"
    
    # Execute test phases
    setup_test_environment
    install_dependencies
    validate_test_files
    run_unit_tests
    generate_test_report
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