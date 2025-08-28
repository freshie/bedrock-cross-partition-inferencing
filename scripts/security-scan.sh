#!/bin/bash

# Security Scan Script for Dual Routing API Gateway
# Scans all files for potential security issues before commit

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Function to scan for hardcoded secrets
scan_secrets() {
    print_header "SCANNING FOR HARDCODED SECRETS AND CREDENTIALS"
    
    local patterns=(
        "password\s*=\s*['\"][^'\"]{8,}['\"]" "Hardcoded password"
        "secret\s*=\s*['\"][^'\"]{16,}['\"]" "Hardcoded secret"
        "api[_-]?key\s*=\s*['\"][^'\"]{16,}['\"]" "Hardcoded API key"
        "access[_-]?key\s*=\s*['\"][^'\"]{16,}['\"]" "Hardcoded access key"
        "bedrock.*api.*key\s*=\s*['\"][^'\"]{16,}['\"]" "Bedrock API key"
        "AKIA[0-9A-Z]{16}" "AWS Access Key ID"
    )
    
    local files_to_scan=(
        "lambda/dual_routing_*.py"
        "infrastructure/dual-routing-*.yaml"
        "scripts/deploy-*.sh"
        "scripts/update-*.sh"
        "config.sh"
    )
    
    for file_pattern in "${files_to_scan[@]}"; do
        for file in $file_pattern; do
            if [[ -f "$file" ]]; then
                log_info "Scanning $file for secrets..."
                
                for ((i=0; i<${#patterns[@]}; i+=2)); do
                    local pattern="${patterns[i]}"
                    local description="${patterns[i+1]}"
                    
                    local matches
                    matches=$(grep -n -i -E "$pattern" "$file" 2>/dev/null || true)
                    
                    if [[ -n "$matches" ]]; then
                        # Filter out test files and example patterns
                        matches=$(echo "$matches" | grep -v "test_" | grep -v "example" | grep -v "placeholder" | grep -v "YOUR_" | grep -v "REPLACE_" || true)
                        
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
    done
    
    log_success "Secret scan completed"
}

# Function to scan for insecure configurations
scan_configurations() {
    print_header "SCANNING FOR INSECURE CONFIGURATIONS"
    
    # Check for overly permissive security groups
    log_info "Checking CloudFormation templates for security issues..."
    
    for template in infrastructure/dual-routing-*.yaml; do
        if [[ -f "$template" ]]; then
            log_info "Scanning $template..."
            
            # Check for 0.0.0.0/0 CIDR blocks (but allow for internet gateways)
            local open_cidrs
            open_cidrs=$(grep -n "0.0.0.0/0" "$template" 2>/dev/null | grep -v "InternetGateway" | grep -v "NatGateway" || true)
            if [[ -n "$open_cidrs" ]]; then
                while IFS= read -r match; do
                    local line_num=$(echo "$match" | cut -d: -f1)
                    report_issue "MEDIUM" "$template" "$line_num" "Overly permissive CIDR block (0.0.0.0/0)"
                done <<< "$open_cidrs"
            fi
            
            # Check for wildcard permissions in IAM policies (but allow CloudWatch and VPC actions)
            local wildcard_perms
            wildcard_perms=$(grep -n '"*"' "$template" 2>/dev/null | grep -v "logs:" | grep -v "ec2:" | grep -v "cloudwatch:" || true)
            if [[ -n "$wildcard_perms" ]]; then
                while IFS= read -r match; do
                    local line_num=$(echo "$match" | cut -d: -f1)
                    report_issue "LOW" "$template" "$line_num" "Potential wildcard permission"
                done <<< "$wildcard_perms"
            fi
        fi
    done
    
    log_success "Configuration scan completed"
}

# Function to scan for hardcoded IPs and URLs
scan_hardcoded_values() {
    print_header "SCANNING FOR HARDCODED VALUES"
    
    local patterns=(
        "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" "Hardcoded IP address"
        "https://[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com" "Hardcoded API Gateway URL"
        "https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" "Hardcoded URL"
        "arn:aws[^:]*:[^:]*:[^:]*:[0-9]{12}:" "Hardcoded AWS account ID"
    )
    
    local files_to_scan=(
        "lambda/dual_routing_*.py"
        "infrastructure/dual-routing-*.yaml"
        "scripts/deploy-*.sh"
    )
    
    for file_pattern in "${files_to_scan[@]}"; do
        for file in $file_pattern; do
            if [[ -f "$file" ]]; then
                log_info "Scanning $file for hardcoded values..."
                
                for ((i=0; i<${#patterns[@]}; i+=2)); do
                    local pattern="${patterns[i]}"
                    local description="${patterns[i+1]}"
                    
                    local matches
                    matches=$(grep -n -E "$pattern" "$file" 2>/dev/null || true)
                    
                    if [[ -n "$matches" ]]; then
                        # Filter out common false positives and legitimate values
                        matches=$(echo "$matches" | grep -v "127.0.0.1" | grep -v "0.0.0.0" | grep -v "localhost" | grep -v "example.com" | grep -v "203.0.113.12" | grep -v "bedrock-runtime.us-east-1.amazonaws.com" | grep -v "10.0." | grep -v "172.16." | grep -v "192.168." | grep -v "test" | grep -v "placeholder" | grep -v "YOUR_" | grep -v "REPLACE_" | grep -v "example" || true)
                        
                        if [[ -n "$matches" ]]; then
                            while IFS= read -r match; do
                                local line_num=$(echo "$match" | cut -d: -f1)
                                report_issue "LOW" "$file" "$line_num" "$description"
                            done <<< "$matches"
                        fi
                    fi
                done
            fi
        done
    done
    
    log_success "Hardcoded values scan completed"
}

# Function to scan for insecure code patterns
scan_code_security() {
    print_header "SCANNING FOR INSECURE CODE PATTERNS"
    
    local patterns=(
        "eval\s*\(" "Use of eval() function"
        "exec\s*\(" "Use of exec() function"
        "os\.system\s*\(" "Use of os.system()"
        "subprocess\.call\s*\([^)]*shell\s*=\s*True" "Subprocess with shell=True"
        "input\s*\(" "Use of input() function"
        "pickle\.loads?\s*\(" "Use of pickle (potential security risk)"
    )
    
    for file in lambda/dual_routing_*.py; do
        if [[ -f "$file" ]]; then
            log_info "Scanning $file for insecure code patterns..."
            
            for ((i=0; i<${#patterns[@]}; i+=2)); do
                local pattern="${patterns[i]}"
                local description="${patterns[i+1]}"
                
                local matches
                matches=$(grep -n -E "$pattern" "$file" 2>/dev/null || true)
                
                if [[ -n "$matches" ]]; then
                    while IFS= read -r match; do
                        local line_num=$(echo "$match" | cut -d: -f1)
                        report_issue "MEDIUM" "$file" "$line_num" "$description"
                    done <<< "$matches"
                fi
            done
        fi
    done
    
    log_success "Code security scan completed"
}

# Function to scan for sensitive data in logs
scan_logging_security() {
    print_header "SCANNING FOR SENSITIVE DATA IN LOGGING"
    
    local patterns=(
        "log.*password[^_]" "Potential password logging"
        "log.*secret[^_]" "Potential secret logging"
        "log.*token[^_]" "Potential token logging"
        "print.*password[^_]" "Potential password in print statement"
        "print.*secret[^_]" "Potential secret in print statement"
    )
    
    for file in lambda/dual_routing_*.py; do
        if [[ -f "$file" ]]; then
            log_info "Scanning $file for sensitive logging..."
            
            for ((i=0; i<${#patterns[@]}; i+=2)); do
                local pattern="${patterns[i]}"
                local description="${patterns[i+1]}"
                
                local matches
                matches=$(grep -n -i -E "$pattern" "$file" 2>/dev/null || true)
                
                if [[ -n "$matches" ]]; then
                    while IFS= read -r match; do
                        local line_num=$(echo "$match" | cut -d: -f1)
                        report_issue "MEDIUM" "$file" "$line_num" "$description"
                    done <<< "$matches"
                fi
            done
        fi
    done
    
    log_success "Logging security scan completed"
}

# Function to check file permissions
check_file_permissions() {
    print_header "CHECKING FILE PERMISSIONS"
    
    # Check for overly permissive files
    local sensitive_files=(
        "scripts/*.sh"
        "lambda/*.py"
        "infrastructure/*.yaml"
    )
    
    for file_pattern in "${sensitive_files[@]}"; do
        for file in $file_pattern; do
            if [[ -f "$file" ]]; then
                local perms
                perms=$(stat -f "%A" "$file" 2>/dev/null || stat -c "%a" "$file" 2>/dev/null || echo "unknown")
                
                if [[ "$perms" == "777" || "$perms" == "666" ]]; then
                    report_issue "MEDIUM" "$file" "1" "Overly permissive file permissions ($perms)"
                fi
            fi
        done
    done
    
    log_success "File permissions check completed"
}

# Function to generate security report
generate_security_report() {
    print_header "GENERATING SECURITY REPORT"
    
    local report_file="$PROJECT_ROOT/outputs/security-scan-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "Security Scan Report"
        echo "Generated: $(date)"
        echo "Project: Dual Routing API Gateway"
        echo ""
        echo "Summary:"
        echo "========"
        echo "Total Security Issues Found: $SECURITY_ISSUES"
        echo ""
        echo "Scan Coverage:"
        echo "- Hardcoded secrets and credentials"
        echo "- Insecure configurations"
        echo "- Hardcoded values (IPs, URLs, ARNs)"
        echo "- Insecure code patterns"
        echo "- Sensitive data in logging"
        echo "- File permissions"
        echo ""
        echo "Files Scanned:"
        echo "- Lambda functions: $(find lambda -name '*.py' 2>/dev/null | wc -l) files"
        echo "- CloudFormation templates: $(find infrastructure -name '*.yaml' 2>/dev/null | wc -l) files"
        echo "- Scripts: $(find scripts -name '*.sh' 2>/dev/null | wc -l) files"
        echo "- Test files: $(find tests -name '*.py' 2>/dev/null | wc -l) files"
        echo ""
        if [[ $SECURITY_ISSUES -eq 0 ]]; then
            echo "✅ SECURITY SCAN PASSED - No issues found"
        else
            echo "❌ SECURITY SCAN FAILED - $SECURITY_ISSUES issues found"
            echo "Review the scan output above for details"
        fi
    } > "$report_file"
    
    log_success "Security report generated: $report_file"
}

# Main execution function
main() {
    print_header "DUAL ROUTING API GATEWAY - SECURITY SCAN"
    log_info "Starting comprehensive security scan..."
    log_info "Project Root: $PROJECT_ROOT"
    
    # Run all security scans
    scan_secrets
    scan_configurations
    scan_hardcoded_values
    scan_code_security
    scan_logging_security
    check_file_permissions
    
    # Generate report
    generate_security_report
    
    print_header "SECURITY SCAN COMPLETED"
    
    if [[ $SECURITY_ISSUES -eq 0 ]]; then
        log_success "🎉 Security scan passed! No issues found."
        log_success "✅ Code is ready for commit"
        exit 0
    else
        log_error "❌ Security scan failed! $SECURITY_ISSUES issues found."
        log_error "Please review and fix the issues before committing"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi