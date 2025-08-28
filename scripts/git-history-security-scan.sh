#!/bin/bash

# Git History Security Scanner
# Scans entire git history for hardcoded secrets, API keys, and sensitive data

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
HISTORY_ISSUES=0

report_history_issue() {
    local severity="$1"
    local commit="$2"
    local file="$3"
    local issue="$4"
    local content="$5"
    
    ((HISTORY_ISSUES++))
    
    if [[ "$severity" == "CRITICAL" ]]; then
        log_error "CRITICAL: Commit $commit in $file - $issue"
        log_error "  Content: $content"
    elif [[ "$severity" == "HIGH" ]]; then
        log_error "HIGH: Commit $commit in $file - $issue"
        log_error "  Content: $content"
    elif [[ "$severity" == "MEDIUM" ]]; then
        log_warning "MEDIUM: Commit $commit in $file - $issue"
    else
        log_info "LOW: Commit $commit in $file - $issue"
    fi
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not in a git repository. Cannot scan git history."
        exit 1
    fi
    
    log_info "Git repository detected. Starting history scan..."
}

# Scan git history for AWS access keys
scan_aws_keys_history() {
    print_header "SCANNING GIT HISTORY FOR AWS ACCESS KEYS"
    
    log_info "Searching for AWS Access Key IDs (AKIA*) in git history..."
    
    # Search for AWS access keys in all commits
    local aws_keys
    aws_keys=$(git log --all --full-history -p -S "AKIA" --source --all | grep -E "^\+.*AKIA[0-9A-Z]{16}" || true)
    
    if [[ -n "$aws_keys" ]]; then
        log_error "Found AWS Access Keys in git history!"
        while IFS= read -r line; do
            local key=$(echo "$line" | grep -oE "AKIA[0-9A-Z]{16}")
            report_history_issue "CRITICAL" "unknown" "unknown" "AWS Access Key found in history" "$key"
        done <<< "$aws_keys"
    else
        log_success "No AWS Access Keys found in git history"
    fi
    
    # Search for potential AWS secret keys (40 character base64-like strings)
    log_info "Searching for potential AWS Secret Keys in git history..."
    
    local secret_keys
    secret_keys=$(git log --all --full-history -p --grep="secret" --grep="key" | grep -E "^\+.*['\"][0-9a-zA-Z/+]{40}['\"]" | head -10 || true)
    
    if [[ -n "$secret_keys" ]]; then
        log_warning "Found potential secret keys in git history (showing first 10):"
        while IFS= read -r line; do
            local secret=$(echo "$line" | grep -oE "['\"][0-9a-zA-Z/+]{40}['\"]")
            report_history_issue "HIGH" "unknown" "unknown" "Potential secret key in history" "$secret"
        done <<< "$secret_keys"
    else
        log_success "No obvious secret keys found in git history"
    fi
}

# Scan git history for API Gateway URLs
scan_api_gateway_history() {
    print_header "SCANNING GIT HISTORY FOR API GATEWAY URLS"
    
    log_info "Searching for hardcoded API Gateway URLs in git history..."
    
    # Search for execute-api URLs in all commits
    local api_urls
    api_urls=$(git log --all --full-history -p | grep -E "^\+.*https://[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com" | head -20 || true)
    
    if [[ -n "$api_urls" ]]; then
        log_warning "Found API Gateway URLs in git history (showing first 20):"
        while IFS= read -r line; do
            local url=$(echo "$line" | grep -oE "https://[a-z0-9]+\.execute-api\.[a-z0-9-]+\.amazonaws\.com[^[:space:]]*")
            # Filter out placeholder URLs
            if [[ ! "$url" =~ (YOUR-API-ID|example|placeholder) ]]; then
                report_history_issue "MEDIUM" "unknown" "unknown" "API Gateway URL in history" "$url"
            fi
        done <<< "$api_urls"
    else
        log_success "No hardcoded API Gateway URLs found in git history"
    fi
}

# Scan git history for Bedrock API keys
scan_bedrock_keys_history() {
    print_header "SCANNING GIT HISTORY FOR BEDROCK API KEYS"
    
    log_info "Searching for Bedrock API keys in git history..."
    
    # Search for bedrock api key patterns
    local bedrock_keys
    bedrock_keys=$(git log --all --full-history -p | grep -iE "^\+.*bedrock.*api.*key.*['\"][^'\"]{16,}['\"]" || true)
    
    if [[ -n "$bedrock_keys" ]]; then
        log_error "Found potential Bedrock API keys in git history!"
        while IFS= read -r line; do
            local key=$(echo "$line" | grep -oE "['\"][^'\"]{16,}['\"]")
            report_history_issue "CRITICAL" "unknown" "unknown" "Bedrock API key in history" "$key"
        done <<< "$bedrock_keys"
    else
        log_success "No Bedrock API keys found in git history"
    fi
}

# Scan git history for other sensitive patterns
scan_sensitive_patterns_history() {
    print_header "SCANNING GIT HISTORY FOR OTHER SENSITIVE PATTERNS"
    
    # Common sensitive patterns
    local patterns=(
        "password\s*=\s*['\"][^'\"]{8,}['\"]" "Hardcoded password"
        "secret\s*=\s*['\"][^'\"]{16,}['\"]" "Hardcoded secret"
        "token\s*=\s*['\"][^'\"]{20,}['\"]" "Hardcoded token"
        "api[_-]?key\s*=\s*['\"][^'\"]{16,}['\"]" "API key"
    )
    
    for ((i=0; i<${#patterns[@]}; i+=2)); do
        local pattern="${patterns[i]}"
        local description="${patterns[i+1]}"
        
        log_info "Searching for $description in git history..."
        
        local matches
        matches=$(git log --all --full-history -p | grep -iE "^\+.*$pattern" | head -5 || true)
        
        if [[ -n "$matches" ]]; then
            log_warning "Found $description in git history (showing first 5):"
            while IFS= read -r line; do
                local value=$(echo "$line" | grep -oE "['\"][^'\"]{8,}['\"]" | head -1)
                # Filter out obvious placeholders
                if [[ ! "$value" =~ (your-|example|placeholder|YOUR_|REPLACE_) ]]; then
                    report_history_issue "HIGH" "unknown" "unknown" "$description in history" "$value"
                fi
            done <<< "$matches"
        else
            log_success "No $description found in git history"
        fi
    done
}

# Get detailed commit information for found issues
get_commit_details() {
    if [[ $HISTORY_ISSUES -gt 0 ]]; then
        print_header "DETAILED COMMIT ANALYSIS"
        
        log_info "Analyzing recent commits for security issues..."
        
        # Get last 10 commits and check for sensitive patterns
        local recent_commits
        recent_commits=$(git log --oneline -10)
        
        log_info "Recent commits:"
        echo "$recent_commits"
        
        # Check if any recent commits mention secrets, keys, or passwords
        local suspicious_commits
        suspicious_commits=$(git log --oneline -20 | grep -iE "(secret|key|password|token|api)" || true)
        
        if [[ -n "$suspicious_commits" ]]; then
            log_warning "Found commits with potentially sensitive keywords:"
            echo "$suspicious_commits"
        fi
    fi
}

# Generate git history security report
generate_history_report() {
    print_header "GENERATING GIT HISTORY SECURITY REPORT"
    
    local report_file="outputs/git-history-security-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "Git History Security Scan Report"
        echo "Generated: $(date)"
        echo "Repository: $(git remote get-url origin 2>/dev/null || echo 'Local repository')"
        echo "Branch: $(git branch --show-current)"
        echo ""
        echo "Summary:"
        echo "========"
        echo "Total Security Issues Found in History: $HISTORY_ISSUES"
        echo ""
        echo "Scan Coverage:"
        echo "- AWS Access Keys (AKIA*)"
        echo "- AWS Secret Keys (40+ char base64)"
        echo "- API Gateway URLs (execute-api)"
        echo "- Bedrock API Keys"
        echo "- Hardcoded passwords, secrets, tokens"
        echo ""
        echo "Repository Stats:"
        echo "- Total commits: $(git rev-list --all --count)"
        echo "- Contributors: $(git shortlog -sn | wc -l)"
        echo "- First commit: $(git log --reverse --oneline | head -1)"
        echo "- Latest commit: $(git log --oneline -1)"
        echo ""
        if [[ $HISTORY_ISSUES -eq 0 ]]; then
            echo "✅ GIT HISTORY SECURITY SCAN PASSED - No issues found"
            echo ""
            echo "The git history is clean of:"
            echo "- AWS credentials"
            echo "- API Gateway URLs"
            echo "- Bedrock API keys"
            echo "- Hardcoded secrets"
        else
            echo "❌ GIT HISTORY SECURITY SCAN FAILED - $HISTORY_ISSUES issues found"
            echo ""
            echo "CRITICAL: Sensitive data found in git history!"
            echo "This data will remain accessible even after cleaning current files."
            echo ""
            echo "Recommended actions:"
            echo "1. Use git filter-branch or BFG Repo-Cleaner to remove sensitive data"
            echo "2. Force push to rewrite history (coordinate with team)"
            echo "3. Rotate any exposed credentials immediately"
            echo "4. Consider creating a new repository if history cannot be cleaned"
        fi
    } > "$report_file"
    
    log_success "Git history security report generated: $report_file"
}

# Main execution
main() {
    print_header "GIT HISTORY SECURITY SCANNER"
    log_info "Scanning entire git history for sensitive data..."
    
    check_git_repo
    
    scan_aws_keys_history
    scan_api_gateway_history
    scan_bedrock_keys_history
    scan_sensitive_patterns_history
    get_commit_details
    
    generate_history_report
    
    print_header "GIT HISTORY SECURITY SCAN COMPLETED"
    
    if [[ $HISTORY_ISSUES -eq 0 ]]; then
        log_success "🎉 Git history security scan passed! No sensitive data found."
        log_success "✅ Repository history is clean and safe"
        exit 0
    else
        log_error "❌ Git history security scan failed! $HISTORY_ISSUES issues found."
        log_error "🚨 CRITICAL: Sensitive data found in git history!"
        log_error ""
        log_error "This is a serious security issue. Even if current files are clean,"
        log_error "the sensitive data remains accessible in git history."
        log_error ""
        log_error "Immediate actions required:"
        log_error "1. Do NOT push this repository to any remote"
        log_error "2. Clean git history using git filter-branch or BFG"
        log_error "3. Rotate any exposed credentials immediately"
        log_error "4. Review security report: outputs/git-history-security-*.txt"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi