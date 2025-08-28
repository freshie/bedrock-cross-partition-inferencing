#!/bin/bash

# Extract VPN Configuration
# This script extracts CloudFormation outputs and VPN status to generate config-vpn.sh

set -e

# Configuration
PROJECT_NAME="cross-partition-inference"
ENVIRONMENT="dev"
OUTPUT_DIR="."
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --govcloud-profile)
            GOVCLOUD_PROFILE="$2"
            shift 2
            ;;
        --commercial-profile)
            COMMERCIAL_PROFILE="$2"
            shift 2
            ;;
        --validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --project-name NAME        Project name (default: cross-partition-inference)"
            echo "  --environment ENV          Environment (default: dev)"
            echo "  --output-dir DIR           Output directory (default: .)"
            echo "  --govcloud-profile PROFILE AWS CLI profile for GovCloud (default: govcloud)"
            echo "  --commercial-profile PROFILE AWS CLI profile for Commercial (default: commercial)"
            echo "  --validate-only            Only validate existing configuration"
            echo "  --verbose                  Enable verbose output"
            echo "  --help, -h                 Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Extract with defaults"
            echo "  $0 --environment prod                 # Extract for prod environment"
            echo "  $0 --output-dir ./config              # Save to ./config directory"
            echo "  $0 --validate-only                    # Validate existing config"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🔧 VPN Configuration Extraction${NC}"
echo -e "${BLUE}Project: ${PROJECT_NAME}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo -e "${BLUE}Output Directory: ${OUTPUT_DIR}${NC}"
echo ""

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 is required but not installed${NC}"
    exit 1
fi

# Check if required Python modules are available
python3 -c "import boto3, json" 2>/dev/null || {
    echo -e "${RED}❌ Required Python modules not found. Please install boto3:${NC}"
    echo "  pip3 install boto3"
    exit 1
}

# Check if AWS CLI profiles exist
check_aws_profile() {
    local profile=$1
    if ! aws configure list-profiles | grep -q "^${profile}$"; then
        echo -e "${RED}❌ AWS CLI profile '${profile}' not found${NC}"
        echo -e "${YELLOW}Please configure the profile using: aws configure --profile ${profile}${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ AWS CLI profile '${profile}' found${NC}"
}

echo -e "${YELLOW}🔍 Checking AWS CLI profiles...${NC}"
check_aws_profile "$GOVCLOUD_PROFILE"
check_aws_profile "$COMMERCIAL_PROFILE"
echo ""

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Prepare Python script arguments
PYTHON_ARGS=(
    "--project-name" "$PROJECT_NAME"
    "--environment" "$ENVIRONMENT"
    "--output-dir" "$OUTPUT_DIR"
    "--govcloud-profile" "$GOVCLOUD_PROFILE"
    "--commercial-profile" "$COMMERCIAL_PROFILE"
)

if [ "$VALIDATE_ONLY" = true ]; then
    PYTHON_ARGS+=("--validate-only")
fi

if [ "$VERBOSE" = true ]; then
    PYTHON_ARGS+=("--verbose")
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the Python configuration manager
echo -e "${YELLOW}🔄 Running VPN configuration extraction...${NC}"

if python3 "${SCRIPT_DIR}/vpn_config_manager.py" "${PYTHON_ARGS[@]}"; then
    echo ""
    echo -e "${GREEN}🎉 VPN configuration extraction completed successfully!${NC}"
    
    # Show generated files
    echo -e "${BLUE}📁 Generated files:${NC}"
    if [ -f "${OUTPUT_DIR}/config-vpn.sh" ]; then
        echo -e "${GREEN}  ✅ ${OUTPUT_DIR}/config-vpn.sh${NC} - Main configuration script"
    fi
    if [ -f "${OUTPUT_DIR}/vpn-config-data.json" ]; then
        echo -e "${GREEN}  ✅ ${OUTPUT_DIR}/vpn-config-data.json${NC} - Raw configuration data"
    fi
    if [ -f "${OUTPUT_DIR}/vpn-config-validation.json" ]; then
        echo -e "${GREEN}  ✅ ${OUTPUT_DIR}/vpn-config-validation.json${NC} - Validation results"
    fi
    
    echo ""
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo -e "${BLUE}  1. Load the configuration:${NC}"
    echo -e "${BLUE}     source ${OUTPUT_DIR}/config-vpn.sh${NC}"
    echo -e "${BLUE}  2. Validate the configuration:${NC}"
    echo -e "${BLUE}     validate_vpn_config${NC}"
    echo -e "${BLUE}  3. Test VPN connectivity:${NC}"
    echo -e "${BLUE}     test_vpn_connectivity${NC}"
    echo -e "${BLUE}  4. Show VPN status:${NC}"
    echo -e "${BLUE}     show_vpn_status${NC}"
    echo ""
    
    # Auto-load configuration if in current directory
    if [ "$OUTPUT_DIR" = "." ] && [ -f "./config-vpn.sh" ]; then
        echo -e "${YELLOW}🔄 Auto-loading configuration...${NC}"
        source "./config-vpn.sh"
        echo ""
    fi
    
    # Show quick status if VPN status script is available
    if [ -f "${SCRIPT_DIR}/get-vpn-status.sh" ]; then
        echo -e "${BLUE}📊 Quick VPN Status:${NC}"
        "${SCRIPT_DIR}/get-vpn-status.sh" summary
    fi
    
else
    echo ""
    echo -e "${RED}❌ VPN configuration extraction failed${NC}"
    echo -e "${YELLOW}Check the error messages above for details${NC}"
    exit 1
fi