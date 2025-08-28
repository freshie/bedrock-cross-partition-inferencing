#!/bin/bash

# Lambda function packaging script
# Creates deployment packages for both Internet and VPN Lambda functions

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LAMBDA_DIR="$PROJECT_ROOT/lambda"
BUILD_DIR="$PROJECT_ROOT/build"

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
    echo "Package Lambda functions for deployment"
    echo ""
    echo "Options:"
    echo "  --internet-only               Package only Internet Lambda function"
    echo "  --vpn-only                    Package only VPN Lambda function"
    echo "  --clean                       Clean build directory before packaging"
    echo "  --validate                    Validate packages after creation"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Package both functions"
    echo "  $0 --internet-only           # Package only Internet Lambda"
    echo "  $0 --vpn-only --clean        # Clean and package only VPN Lambda"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    print_header "VALIDATING PREREQUISITES"
    
    # Check Python
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
    
    # Check required files
    local required_files=(
        "$LAMBDA_DIR/dual_routing_internet_lambda.py"
        "$LAMBDA_DIR/dual_routing_vpn_lambda.py"
        "$LAMBDA_DIR/dual_routing_error_handler.py"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file not found: $file"
            exit 1
        fi
    done
    
    log_success "All required Lambda files found"
}

# Function to clean build directory
clean_build_directory() {
    if [[ "$CLEAN" == "true" ]]; then
        print_header "CLEANING BUILD DIRECTORY"
        
        if [[ -d "$BUILD_DIR" ]]; then
            rm -rf "$BUILD_DIR"
            log_success "Build directory cleaned"
        fi
    fi
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
}

# Function to package Internet Lambda function
package_internet_lambda() {
    print_header "PACKAGING INTERNET LAMBDA FUNCTION"
    
    local package_dir="$BUILD_DIR/internet-lambda-package"
    local package_file="$BUILD_DIR/internet-lambda-deployment.zip"
    
    # Create package directory
    mkdir -p "$package_dir"
    
    log_info "Creating Internet Lambda deployment package..."
    
    # Copy Lambda function files
    cp "$LAMBDA_DIR/dual_routing_internet_lambda.py" "$package_dir/"
    cp "$LAMBDA_DIR/dual_routing_error_handler.py" "$package_dir/"
    
    log_success "Copied Internet Lambda function files"
    
    # Install dependencies if requirements.txt exists
    if [[ -f "$LAMBDA_DIR/requirements.txt" ]]; then
        log_info "Installing Python dependencies for Internet Lambda..."
        
        # Install dependencies to package directory
        python3 -m pip install -r "$LAMBDA_DIR/requirements.txt" -t "$package_dir" --quiet --no-deps
        
        log_success "Python dependencies installed"
    fi
    
    # Create deployment package
    log_info "Creating Internet Lambda deployment ZIP package..."
    
    cd "$package_dir"
    zip -r "$package_file" . -q
    cd "$PROJECT_ROOT"
    
    local package_size
    package_size=$(du -h "$package_file" | cut -f1)
    
    log_success "Internet Lambda deployment package created: $package_file ($package_size)"
    
    INTERNET_PACKAGE="$package_file"
}

# Function to package VPN Lambda function
package_vpn_lambda() {
    print_header "PACKAGING VPN LAMBDA FUNCTION"
    
    local package_dir="$BUILD_DIR/vpn-lambda-package"
    local package_file="$BUILD_DIR/vpn-lambda-deployment.zip"
    
    # Create package directory
    mkdir -p "$package_dir"
    
    log_info "Creating VPN Lambda deployment package..."
    
    # Copy Lambda function files
    cp "$LAMBDA_DIR/dual_routing_vpn_lambda.py" "$package_dir/"
    cp "$LAMBDA_DIR/dual_routing_error_handler.py" "$package_dir/"
    
    log_success "Copied VPN Lambda function files"
    
    # Install dependencies if requirements.txt exists
    if [[ -f "$LAMBDA_DIR/requirements.txt" ]]; then
        log_info "Installing Python dependencies for VPN Lambda..."
        
        # Install dependencies to package directory
        python3 -m pip install -r "$LAMBDA_DIR/requirements.txt" -t "$package_dir" --quiet --no-deps
        
        log_success "Python dependencies installed"
    fi
    
    # Create deployment package
    log_info "Creating VPN Lambda deployment ZIP package..."
    
    cd "$package_dir"
    zip -r "$package_file" . -q
    cd "$PROJECT_ROOT"
    
    local package_size
    package_size=$(du -h "$package_file" | cut -f1)
    
    log_success "VPN Lambda deployment package created: $package_file ($package_size)"
    
    VPN_PACKAGE="$package_file"
}

# Function to validate packages
validate_packages() {
    if [[ "$VALIDATE" != "true" ]]; then
        return 0
    fi
    
    print_header "VALIDATING DEPLOYMENT PACKAGES"
    
    # Validate Internet Lambda package
    if [[ -n "$INTERNET_PACKAGE" && -f "$INTERNET_PACKAGE" ]]; then
        log_info "Validating Internet Lambda package..."
        
        # Check package contents
        local contents
        contents=$(unzip -l "$INTERNET_PACKAGE" 2>/dev/null | grep -E "\.(py)$" | wc -l)
        
        if [[ $contents -ge 2 ]]; then
            log_success "Internet Lambda package contains expected Python files"
        else
            log_warning "Internet Lambda package may be missing Python files"
        fi
        
        # Check package size
        local size_bytes
        size_bytes=$(stat -f%z "$INTERNET_PACKAGE" 2>/dev/null || stat -c%s "$INTERNET_PACKAGE" 2>/dev/null)
        local max_size=$((50 * 1024 * 1024))  # 50MB
        
        if [[ $size_bytes -gt $max_size ]]; then
            log_warning "Internet Lambda package size exceeds 50MB direct upload limit"
        else
            log_success "Internet Lambda package size is within limits"
        fi
    fi
    
    # Validate VPN Lambda package
    if [[ -n "$VPN_PACKAGE" && -f "$VPN_PACKAGE" ]]; then
        log_info "Validating VPN Lambda package..."
        
        # Check package contents
        local contents
        contents=$(unzip -l "$VPN_PACKAGE" 2>/dev/null | grep -E "\.(py)$" | wc -l)
        
        if [[ $contents -ge 2 ]]; then
            log_success "VPN Lambda package contains expected Python files"
        else
            log_warning "VPN Lambda package may be missing Python files"
        fi
        
        # Check package size
        local size_bytes
        size_bytes=$(stat -f%z "$VPN_PACKAGE" 2>/dev/null || stat -c%s "$VPN_PACKAGE" 2>/dev/null)
        local max_size=$((50 * 1024 * 1024))  # 50MB
        
        if [[ $size_bytes -gt $max_size ]]; then
            log_warning "VPN Lambda package size exceeds 50MB direct upload limit"
        else
            log_success "VPN Lambda package size is within limits"
        fi
    fi
}

# Function to generate packaging report
generate_packaging_report() {
    print_header "GENERATING PACKAGING REPORT"
    
    local report_file="$BUILD_DIR/lambda-packaging-report-$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Lambda Function Packaging Report"
        echo "Generated: $(date)"
        echo ""
        echo "Packaging Configuration:"
        echo "- Build Directory: $BUILD_DIR"
        echo "- Lambda Source Directory: $LAMBDA_DIR"
        echo "- Clean Build: ${CLEAN:-false}"
        echo "- Validation: ${VALIDATE:-false}"
        echo ""
        echo "Packages Created:"
        
        if [[ -n "$INTERNET_PACKAGE" && -f "$INTERNET_PACKAGE" ]]; then
            local internet_size
            internet_size=$(du -h "$INTERNET_PACKAGE" | cut -f1)
            echo "- Internet Lambda: $INTERNET_PACKAGE ($internet_size)"
        else
            echo "- Internet Lambda: Not packaged"
        fi
        
        if [[ -n "$VPN_PACKAGE" && -f "$VPN_PACKAGE" ]]; then
            local vpn_size
            vpn_size=$(du -h "$VPN_PACKAGE" | cut -f1)
            echo "- VPN Lambda: $VPN_PACKAGE ($vpn_size)"
        else
            echo "- VPN Lambda: Not packaged"
        fi
        
        echo ""
        echo "Files Included:"
        echo "- dual_routing_internet_lambda.py (Internet Lambda handler)"
        echo "- dual_routing_vpn_lambda.py (VPN Lambda handler)"
        echo "- dual_routing_error_handler.py (Shared error handling)"
        
        if [[ -f "$LAMBDA_DIR/requirements.txt" ]]; then
            echo "- Python dependencies from requirements.txt"
        else
            echo "- No additional Python dependencies"
        fi
        
        echo ""
        echo "Next Steps:"
        echo "1. Deploy Internet Lambda: ./scripts/deploy-internet-lambda.sh"
        echo "2. Deploy VPN Lambda: ./scripts/deploy-vpn-lambda.sh"
        echo "3. Test both Lambda functions"
    } > "$report_file"
    
    log_success "Packaging report generated: $report_file"
}

# Main execution function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --internet-only)
                INTERNET_ONLY="true"
                shift
                ;;
            --vpn-only)
                VPN_ONLY="true"
                shift
                ;;
            --clean)
                CLEAN="true"
                shift
                ;;
            --validate)
                VALIDATE="true"
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
    
    print_header "LAMBDA FUNCTION PACKAGING"
    log_info "Build Directory: $BUILD_DIR"
    log_info "Lambda Source Directory: $LAMBDA_DIR"
    
    # Execute packaging steps
    validate_prerequisites
    clean_build_directory
    
    # Package functions based on options
    if [[ "$VPN_ONLY" == "true" ]]; then
        package_vpn_lambda
    elif [[ "$INTERNET_ONLY" == "true" ]]; then
        package_internet_lambda
    else
        package_internet_lambda
        package_vpn_lambda
    fi
    
    validate_packages
    generate_packaging_report
    
    print_header "PACKAGING COMPLETED SUCCESSFULLY"
    log_success "Lambda function packaging completed"
    
    if [[ -n "$INTERNET_PACKAGE" ]]; then
        log_info "Internet Lambda package: $INTERNET_PACKAGE"
    fi
    
    if [[ -n "$VPN_PACKAGE" ]]; then
        log_info "VPN Lambda package: $VPN_PACKAGE"
    fi
    
    log_info "Use the deployment scripts to deploy the packaged functions"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi