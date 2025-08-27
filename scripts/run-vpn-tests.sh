#!/bin/bash

# Cross-Partition Routing Test Runner
# This script runs comprehensive tests for both internet and VPN routing methods

set -e

# Configuration
PROJECT_NAME="cross-partition-inference"
ENVIRONMENT="dev"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"
TEST_TYPE="both"  # both, internet, vpn, comparison

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🧪 Cross-Partition Routing Test Suite${NC}"
echo -e "${BLUE}Project: $PROJECT_NAME${NC}"
echo -e "${BLUE}Environment: $ENVIRONMENT${NC}"
echo ""

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --test-type TYPE      Test type: both, internet, vpn, comparison (default: both)"
    echo "  --project-name NAME   Project name (default: cross-partition-inference)"
    echo "  --environment ENV     Environment (default: dev)"
    echo "  --help, -h            Show this help message"
    echo ""
    echo "Test Types:"
    echo "  both        Run both internet and VPN tests separately"
    echo "  internet    Run only internet routing tests"
    echo "  vpn         Run only VPN routing tests"
    echo "  comparison  Run comparison tests between both methods"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Run both test types"
    echo "  $0 --test-type internet               # Test internet routing only"
    echo "  $0 --test-type vpn                    # Test VPN routing only"
    echo "  $0 --test-type comparison             # Compare both methods"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test-type)
            TEST_TYPE="$2"
            shift 2
            ;;
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done



# Main execution
echo -e "${BLUE}Test Configuration:${NC}"
echo "  Test Type: $TEST_TYPE"
echo "  Environment: $ENVIRONMENT"
echo "  Project: $PROJECT_NAME"
echo ""

# Set environment variables
export PROJECT_NAME="$PROJECT_NAME"
export ENVIRONMENT="$ENVIRONMENT"

# Load configuration if available
if [ -f "config-vpn.sh" ]; then
    echo -e "${YELLOW}📋 Loading VPN configuration...${NC}"
    source config-vpn.sh
else
    echo -e "${YELLOW}⚠️ config-vpn.sh not found, some tests may be skipped${NC}"
fi

# Check Python dependencies
echo -e "${YELLOW}🔍 Checking Python dependencies...${NC}"
python3 -c "import boto3, pytest" 2>/dev/null || {
    echo -e "${RED}❌ Required Python modules not found. Please install:${NC}"
    echo "  pip3 install boto3 pytest requests"
    exit 1
}

# Run tests based on type
case "$TEST_TYPE" in
    "internet")
        echo -e "${YELLOW}🌐 Running Internet Routing Tests...${NC}"
        python3 tests/test_internet_routing.py
        ;;
    
    "vpn")
        echo -e "${YELLOW}🔗 Running VPN Routing Tests...${NC}"
        python3 tests/test_vpn_routing.py
        ;;
    
    "comparison")
        echo -e "${YELLOW}⚖️ Running Routing Comparison Tests...${NC}"
        python3 tests/test_routing_comparison.py
        ;;
    
    "both")
        echo -e "${YELLOW}🌐 Running Internet Routing Tests...${NC}"
        python3 tests/test_internet_routing.py
        INTERNET_EXIT_CODE=$?
        
        echo ""
        echo -e "${YELLOW}🔗 Running VPN Routing Tests...${NC}"
        python3 tests/test_vpn_routing.py
        VPN_EXIT_CODE=$?
        
        echo ""
        echo -e "${BLUE}📊 Test Summary${NC}"
        echo "=================================="
        
        if [ $INTERNET_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Internet routing tests: PASSED${NC}"
        else
            echo -e "${RED}❌ Internet routing tests: FAILED${NC}"
        fi
        
        if [ $VPN_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ VPN routing tests: PASSED${NC}"
        else
            echo -e "${RED}❌ VPN routing tests: FAILED${NC}"
        fi
        
        # Exit with failure if any tests failed
        if [ $INTERNET_EXIT_CODE -ne 0 ] || [ $VPN_EXIT_CODE -ne 0 ]; then
            echo -e "${RED}❌ Some tests failed${NC}"
            exit 1
        else
            echo -e "${GREEN}✅ All tests passed${NC}"
            exit 0
        fi
        ;;
    
    *)
        echo -e "${RED}❌ Unknown test type: $TEST_TYPE${NC}"
        echo "Valid types: both, internet, vpn, comparison"
        exit 1
        ;;
esac

echo -e "${GREEN}✅ Tests completed${NC}"