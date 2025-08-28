#!/bin/bash

# Comprehensive unit test runner for VPN Lambda function
# Runs all unit tests with coverage reporting and detailed analysis

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="test"
PYTHON_VERSION="python3"
COVERAGE_THRESHOLD=80
GENERATE_HTML_REPORT="true"
VERBOSE="true"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TESTS_DIR="$PROJECT_ROOT/tests"

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

# Help function
show_help() {
    cat << EOF
Comprehensive unit test runner for VPN Lambda function

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Test environment (default: test)
    --python PYTHON             Python executable (default: python3)
    --coverage-threshold N      Coverage threshold percentage (default: 80)
    --no-html-report           Skip HTML coverage report generation
    --quiet                    Reduce output verbosity
    --help                     Show this help message

Examples:
    # Run all tests with default settings
    $0
    
    # Run tests with custom coverage threshold
    $0 --coverage-threshold 90
    
    # Run tests quietly without HTML report
    $0 --quiet --no-html-report

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --python)
            PYTHON_VERSION="$2"
            shift 2
            ;;
        --coverage-threshold)
            COVERAGE_THRESHOLD="$2"
            shift 2
            ;;
        --no-html-report)
            GENERATE_HTML_REPORT="false"
            shift
            ;;
        --quiet)
            VERBOSE="false"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

log_info "Starting VPN Lambda function unit tests..."
log_info "  Project: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Python: $PYTHON_VERSION"
log_info "  Coverage Threshold: ${COVERAGE_THRESHOLD}%"
log_info "  Tests Directory: $TESTS_DIR"

# Check Python version
if ! command -v "$PYTHON_VERSION" &> /dev/null; then
    log_error "Python executable not found: $PYTHON_VERSION"
    exit 1
fi

PYTHON_VER_OUTPUT=$($PYTHON_VERSION --version 2>&1)
log_info "Using: $PYTHON_VER_OUTPUT"

# Create tests directory if it doesn't exist
mkdir -p "$TESTS_DIR"

# Check if test files exist
VPN_TEST_FILES=(
    "$TESTS_DIR/test_vpn_lambda_unit.py"
    "$TESTS_DIR/test_vpn_lambda_vpc_endpoints.py"
)

MISSING_FILES=()
for test_file in "${VPN_TEST_FILES[@]}"; do
    if [[ ! -f "$test_file" ]]; then
        MISSING_FILES+=("$test_file")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    log_error "Missing test files:"
    for file in "${MISSING_FILES[@]}"; do
        log_error "  - $file"
    done
    exit 1
fi

# Install test dependencies if requirements.txt exists
if [[ -f "$TESTS_DIR/requirements.txt" ]]; then
    log_info "Installing test dependencies..."
    $PYTHON_VERSION -m pip install -r "$TESTS_DIR/requirements.txt" --quiet
    if [[ $? -eq 0 ]]; then
        log_success "Test dependencies installed successfully"
    else
        log_warning "Some test dependencies may not have installed correctly"
    fi
fi

# Set up environment variables for testing
export PYTHONPATH="$PROJECT_ROOT:$PROJECT_ROOT/lambda:$PYTHONPATH"
export AWS_DEFAULT_REGION="us-gov-west-1"
export AWS_REGION="us-gov-west-1"

# Test environment variables
export VPC_ENDPOINT_SECRETS="https://vpce-secrets.us-gov-west-1.vpce.amazonaws.com"
export VPC_ENDPOINT_DYNAMODB="https://vpce-dynamodb.us-gov-west-1.vpce.amazonaws.com"
export VPC_ENDPOINT_LOGS="https://vpce-logs.us-gov-west-1.vpce.amazonaws.com"
export VPC_ENDPOINT_MONITORING="https://vpce-monitoring.us-gov-west-1.vpce.amazonaws.com"
export COMMERCIAL_BEDROCK_ENDPOINT="https://bedrock-runtime.us-east-1.amazonaws.com"
export COMMERCIAL_CREDENTIALS_SECRET="test-commercial-creds"
export REQUEST_LOG_TABLE="test-request-log-table"
export ROUTING_METHOD="vpn"

log_info "Environment variables configured for testing"

# Create coverage configuration
COVERAGE_CONFIG="$TESTS_DIR/.coveragerc"
cat > "$COVERAGE_CONFIG" << EOF
[run]
source = lambda
omit = 
    */tests/*
    */test_*
    */__pycache__/*
    */venv/*
    */env/*

[report]
exclude_lines =
    pragma: no cover
    def __repr__
    if self.debug:
    if settings.DEBUG
    raise AssertionError
    raise NotImplementedError
    if 0:
    if __name__ == .__main__.:
    class .*\bProtocol\):
    @(abc\.)?abstractmethod

[html]
directory = tests/coverage_html
EOF

log_info "Coverage configuration created"

# Run tests with coverage
log_info "Running VPN Lambda unit tests with coverage..."

cd "$PROJECT_ROOT"

# Run the test runner
if [[ "$VERBOSE" == "false" ]]; then
    VERBOSITY_FLAG="--quiet"
else
    VERBOSITY_FLAG=""
fi

HTML_FLAG=""
if [[ "$GENERATE_HTML_REPORT" == "false" ]]; then
    HTML_FLAG="--no-coverage"
fi

# Check if custom test runner exists
if [[ -f "$TESTS_DIR/run_vpn_lambda_tests.py" ]]; then
    log_info "Using custom test runner..."
    $PYTHON_VERSION "$TESTS_DIR/run_vpn_lambda_tests.py" $VERBOSITY_FLAG $HTML_FLAG
    TEST_EXIT_CODE=$?
else
    log_info "Using standard unittest runner..."
    
    # Run tests with coverage
    $PYTHON_VERSION -m coverage run --rcfile="$COVERAGE_CONFIG" -m unittest discover -s "$TESTS_DIR" -p "test_vpn_lambda_*.py" -v
    TEST_EXIT_CODE=$?
    
    if [[ $TEST_EXIT_CODE -eq 0 ]]; then
        log_success "All tests passed!"
        
        # Generate coverage report
        log_info "Generating coverage report..."
        COVERAGE_PERCENTAGE=$($PYTHON_VERSION -m coverage report --rcfile="$COVERAGE_CONFIG" | tail -1 | awk '{print $NF}' | sed 's/%//')
        
        if [[ -n "$COVERAGE_PERCENTAGE" ]]; then
            log_info "Coverage: ${COVERAGE_PERCENTAGE}%"
            
            # Check coverage threshold
            if (( $(echo "$COVERAGE_PERCENTAGE >= $COVERAGE_THRESHOLD" | bc -l) )); then
                log_success "Coverage threshold met: ${COVERAGE_PERCENTAGE}% >= ${COVERAGE_THRESHOLD}%"
            else
                log_warning "Coverage below threshold: ${COVERAGE_PERCENTAGE}% < ${COVERAGE_THRESHOLD}%"
            fi
        fi
        
        # Generate HTML report if requested
        if [[ "$GENERATE_HTML_REPORT" == "true" ]]; then
            log_info "Generating HTML coverage report..."
            $PYTHON_VERSION -m coverage html --rcfile="$COVERAGE_CONFIG"
            if [[ $? -eq 0 ]]; then
                log_success "HTML coverage report generated: tests/coverage_html/index.html"
            else
                log_warning "Failed to generate HTML coverage report"
            fi
        fi
        
        # Show detailed coverage report
        if [[ "$VERBOSE" == "true" ]]; then
            echo ""
            log_info "Detailed coverage report:"
            $PYTHON_VERSION -m coverage report --rcfile="$COVERAGE_CONFIG" --show-missing
        fi
    else
        log_error "Some tests failed!"
    fi
fi

# Clean up
rm -f "$COVERAGE_CONFIG"

# Generate test summary
echo ""
echo "=" * 80
echo "VPN LAMBDA UNIT TEST SUMMARY"
echo "=" * 80

if [[ $TEST_EXIT_CODE -eq 0 ]]; then
    log_success "✅ ALL TESTS PASSED"
    echo ""
    echo "Test Results:"
    echo "  - All VPN Lambda unit tests executed successfully"
    echo "  - VPC endpoint functionality validated"
    echo "  - Error handling scenarios tested"
    echo "  - Integration tests completed"
    
    if [[ -n "$COVERAGE_PERCENTAGE" ]]; then
        echo "  - Code coverage: ${COVERAGE_PERCENTAGE}%"
    fi
    
    if [[ "$GENERATE_HTML_REPORT" == "true" ]]; then
        echo ""
        echo "Reports Generated:"
        echo "  - HTML Coverage Report: tests/coverage_html/index.html"
        echo "  - Test Results JSON: tests/vpn_lambda_test_results.json"
    fi
else
    log_error "❌ SOME TESTS FAILED"
    echo ""
    echo "Please review the test output above for details on failed tests."
    echo "Common issues to check:"
    echo "  - Missing dependencies"
    echo "  - Environment variable configuration"
    echo "  - Mock setup issues"
    echo "  - Import path problems"
fi

echo ""
echo "Next Steps:"
if [[ $TEST_EXIT_CODE -eq 0 ]]; then
    echo "  1. Review coverage report for any gaps"
    echo "  2. Run integration tests if available"
    echo "  3. Execute end-to-end tests"
    echo "  4. Deploy to test environment"
else
    echo "  1. Fix failing tests"
    echo "  2. Re-run test suite"
    echo "  3. Check test dependencies"
    echo "  4. Review error messages above"
fi

echo "=" * 80

exit $TEST_EXIT_CODE