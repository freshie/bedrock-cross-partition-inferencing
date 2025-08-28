#!/bin/bash

# Production Security Scan - Focus on Core Files Only
# Scans only production-ready files for real security issues

set -e

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

# Security issue counter
SECURITY_ISSUES=0

# Function to report security issue
report_issue() {
    local severity="$1"
    local file="$2"
    local line="$3"
    local issue="$4"
    
    ((SECURITY_ISSUES++))
    
    if [[ "$severity" == "HIGH" ]]; then
        log_error "HIGH: $file:$line - $issue"
    elif [[ "$severity" == "MEDIUM" ]]; then
        log_warning "MEDIUM: $file:$line - $issue"
    else
        log_info "LOW: $file:$line - $issue"
    fi
}

# Function to scan for real hardcoded secrets
scan_production_secrets() {
    print_header "SCANNING PRODUCTION FILES FOR HARDCODED SECRETS"
    
    local production_files=(
        "lambda/dual_routing_vpn_lambda.py"
        "lambda/dual_routing_internet_lambda.py"
        "lambda/dual_routing_authorizer.py"
        "lambda/dual_routing_error_handler.py"
        "lambda/dual_routing_metrics_processor.py"
        "infrastructure/dual-routing-api-gateway.yaml"
        "infrastructure/dual-routing-auth.yaml"
        "infrastructure/dual-routing-monitoring.yaml"
        "infrastructure/dual-routing-vpn-lambda.yaml"
        "infrastructure/dual-routing-vpn-infrastructure.yaml"
        "config.sh"
    )
    
    local secret_patterns=(
        "password\s*=\s*['\"][^'\"]{8,}['\"]" "Hardcoded password"
        "secret\s*=\s*['\"][^'\"]{20,}['\"]" "Hardcoded secret"
        "api[_-]?key\s*=\s*['\"][^'\"]{20,}['\"]" "Hardcoded API key"
        "AKIA[0-9A-Z]{16}" "AWS Access Key ID"
        "['\"][0-9a-zA-Z/+]{40}['\"]" "Potential AWS Secret Key"
    )
    
    for file in "${production_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Scanning $file for secrets..."
            
            for ((i=0; i<${#secret_patterns[@]}; i+=2)); do
                local pattern="${secret_patterns[i]}"
                local description="${secret_patterns[i+1]}"
                
                local matches
                matches=$(grep -n -E "$pattern" "$file" 2>/dev/null || true)
                
                if [[ -n "$matches" ]]; then
                    # Filter out obvious placeholders and examples
                    matches=$(echo "$matches" | grep -v "YOUR_" | grep -v "REPLACE_" | grep -v "EXAMPLE_" | grep -v "placeholder" | grep -v "example" || true)
                    
                    if [[ -n "$matches" ]]; then
                        while IFS= read -r match; do
                            local line_num=$(echo "$match" | cut -d: -f1)
                            report_issue "HIGH" "$file" "$line_num" "$description"
                        done <<< "$matches"
                    fi
                fi
            done
        fi
    done
    
    log_success "Production secret scan completed"
}

# Function to scan for insecure network configurations
scan_network_security() {
    print_header "SCANNING NETWORK SECURITY CONFIGURATIONS"
    
    local templates=(
        "infrastructure/dual-routing-vpn-infrastructure.yaml"
        "infrastructure/dual-routing-api-gateway.yaml"
    )
    
    for template in "${templates[@]}"; do
        if [[ -f "$template" ]]; then
            log_info "Scanning $template for network security..."
            
            # Check for overly permissive CIDR blocks (excluding legitimate internet access)
            local suspicious_cidrs
            suspicious_cidrs=$(grep -n "0.0.0.0/0" "$template" 2>/dev/null | grep -v "InternetGateway" | grep -v "NatGateway" | grep -v "Route" || true)
            
            if [[ -n "$suspicious_cidrs" ]]; then
                while IFS= read -r match; do
                    local line_num=$(echo "$match" | cut -d: -f1)
                    report_issue "MEDIUM" "$template" "$line_num" "Potentially insecure CIDR block (0.0.0.0/0)"
                done <<< "$suspicious_cidrs"
            fi
        fi
    done
    
    log_success "Network security scan completed"
}

# Function to scan for insecure code patterns in Lambda functions
scan_lambda_security() {
    print_header "SCANNING LAMBDA FUNCTIONS FOR SECURITY ISSUES"
    
    local lambda_files=(
        "lambda/dual_routing_vpn_lambda.py"
        "lambda/dual_routing_internet_lambda.py"
        "lambda/dual_routing_authorizer.py"
        "lambda/dual_routing_error_handler.py"
        "lambda/dual_routing_metrics_processor.py"
    )
    
    local insecure_patterns=(
        "eval\s*\(" "Use of eval() function"
        "exec\s*\(" "Use of exec() function"
        "os\.system\s*\(" "Use of os.system()"
        "subprocess\.call\s*\([^)]*shell\s*=\s*True" "Subprocess with shell=True"
        "pickle\.loads?\s*\(" "Use of pickle (potential security risk)"
    )
    
    for file in "${lambda_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Scanning $file for insecure patterns..."
            
            for ((i=0; i<${#insecure_patterns[@]}; i+=2)); do
                local pattern="${insecure_patterns[i]}"
                local description="${insecure_patterns[i+1]}"
                
                local matches
                matches=$(grep -n -E "$pattern" "$file" 2>/dev/null || true)
                
                if [[ -n "$matches" ]]; then
                    while IFS= read -r match; do
                        local line_num=$(echo "$match" | cut -d: -f1)
                        report_issue "HIGH" "$file" "$line_num" "$description"
                    done <<< "$matches"
                fi
            done
        fi
    done
    
    log_success "Lambda security scan completed"
}

# Function to check for sensitive data in logs
scan_logging_security() {
    print_header "SCANNING FOR SENSITIVE DATA IN LOGGING"
    
    local lambda_files=(
        "lambda/dual_routing_vpn_lambda.py"
        "lambda/dual_routing_internet_lambda.py"
        "lambda/dual_routing_authorizer.py"
        "lambda/dual_routing_error_handler.py"
        "lambda/dual_routing_metrics_processor.py"
    )
    
    for file in "${lambda_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Scanning $file for sensitive logging..."
            
            # Look for actual sensitive data being logged (not just variable names)
            local sensitive_logging
            sensitive_logging=$(grep -n -E "log.*['\"][^'\"]*password[^'\"]*['\"]|log.*['\"][^'\"]*secret[^'\"]*['\"]|log.*['\"][^'\"]*token[^'\"]*['\"]" "$file" 2>/dev/null || true)
            
            if [[ -n "$sensitive_logging" ]]; then
                while IFS= read -r match; do
                    local line_num=$(echo "$match" | cut -d: -f1)
                    report_issue "MEDIUM" "$file" "$line_num" "Potential sensitive data in logging"
                done <<< "$sensitive_logging"
            fi
        fi
    done
    
    log_success "Logging security scan completed"
}

# Main execution function
main() {
    print_header "PRODUCTION SECURITY SCAN - DUAL ROUTING API GATEWAY"
    log_info "Scanning production-ready files for security issues..."
    
    # Run focused security scans
    scan_production_secrets
    scan_network_security
    scan_lambda_security
    scan_logging_security
    
    print_header "PRODUCTION SECURITY SCAN COMPLETED"
    
    if [[ $SECURITY_ISSUES -eq 0 ]]; then
        log_success "🎉 Production security scan passed! No issues found."
        log_success "✅ Code is ready for commit"
        exit 0
    else
        log_error "❌ Production security scan failed! $SECURITY_ISSUES issues found."
        log_error "Please review and fix the issues before committing"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi