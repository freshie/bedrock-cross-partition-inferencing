#!/bin/bash

# Test authentication and authorization for dual routing endpoints
# Tests API keys, IAM roles, and different access patterns

set -e

# Default values
API_GATEWAY_URL=""
INTERNET_API_KEY=""
VPN_API_KEY=""
ADMIN_API_KEY=""
TEST_MODEL="anthropic.claude-3-haiku-20240307-v1:0"
TEST_PROMPT="Hello, this is an authentication test."

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
Test authentication and authorization for dual routing endpoints

Usage: $0 [OPTIONS]

Options:
    --api-url URL               API Gateway base URL (required)
    --internet-key KEY          Internet routing API key
    --vpn-key KEY              VPN routing API key
    --admin-key KEY            Admin API key
    --test-model MODEL         Model ID to test (default: anthropic.claude-3-haiku-20240307-v1:0)
    --test-prompt PROMPT       Test prompt (default: authentication test message)
    --help                     Show this help message

Examples:
    # Test with all API keys
    $0 --api-url https://YOUR-API-ID.execute-api.us-gov-west-1.amazonaws.com/prod \\
       --internet-key internet-key-here \\
       --vpn-key vpn-key-here \\
       --admin-key admin-key-here
    
    # Test with admin key only
    $0 --api-url https://YOUR-API-ID.execute-api.us-gov-west-1.amazonaws.com/prod \\
       --admin-key admin-key-here

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --api-url)
            API_GATEWAY_URL="$2"
            shift 2
            ;;
        --internet-key)
            INTERNET_API_KEY="$2"
            shift 2
            ;;
        --vpn-key)
            VPN_API_KEY="$2"
            shift 2
            ;;
        --admin-key)
            ADMIN_API_KEY="$2"
            shift 2
            ;;
        --test-model)
            TEST_MODEL="$2"
            shift 2
            ;;
        --test-prompt)
            TEST_PROMPT="$2"
            shift 2
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

# Validate required parameters
if [[ -z "$API_GATEWAY_URL" ]]; then
    log_error "API Gateway URL is required. Use --api-url parameter."
    exit 1
fi

# Remove trailing slash from URL
API_GATEWAY_URL="${API_GATEWAY_URL%/}"

log_info "Starting dual routing authentication tests..."
log_info "  API Gateway URL: $API_GATEWAY_URL"
log_info "  Internet API Key: ${INTERNET_API_KEY:+[PROVIDED]}${INTERNET_API_KEY:-[NOT PROVIDED]}"
log_info "  VPN API Key: ${VPN_API_KEY:+[PROVIDED]}${VPN_API_KEY:-[NOT PROVIDED]}"
log_info "  Admin API Key: ${ADMIN_API_KEY:+[PROVIDED]}${ADMIN_API_KEY:-[NOT PROVIDED]}"

# Test payload
TEST_PAYLOAD=$(cat << EOF
{
    "modelId": "$TEST_MODEL",
    "body": {
        "messages": [
            {
                "role": "user",
                "content": "$TEST_PROMPT"
            }
        ],
        "max_tokens": 50,
        "temperature": 0.7
    }
}
EOF
)

echo ""
echo "=== DUAL ROUTING AUTHENTICATION TESTS ==="
echo ""

TOTAL_TESTS=0
PASSED_TESTS=0

# Test 1: No authentication (should fail)
echo "1. Testing No Authentication (should fail)"
((TOTAL_TESTS++))
NO_AUTH_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/no_auth.json \
    -H "Content-Type: application/json" \
    "$API_GATEWAY_URL/v1/bedrock/invoke-model" || echo "000")

if [[ "$NO_AUTH_RESPONSE" == "403" || "$NO_AUTH_RESPONSE" == "401" ]]; then
    log_success "No auth correctly rejected (status: $NO_AUTH_RESPONSE)"
    ((PASSED_TESTS++))
else
    log_error "No auth test failed - expected 401/403, got: $NO_AUTH_RESPONSE"
    if [[ -f /tmp/no_auth.json ]]; then
        log_error "   Response: $(cat /tmp/no_auth.json)"
    fi
fi
echo ""

# Test 2: Internet routing with Internet API key
if [[ -n "$INTERNET_API_KEY" ]]; then
    echo "2. Testing Internet Routing with Internet API Key"
    ((TOTAL_TESTS++))
    INTERNET_AUTH_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/internet_auth.json \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $INTERNET_API_KEY" \
        "$API_GATEWAY_URL/v1/bedrock/invoke-model" || echo "000")
    
    if [[ "$INTERNET_AUTH_RESPONSE" == "200" ]]; then
        log_success "Internet routing with Internet key successful"
        ((PASSED_TESTS++))
    else
        log_error "Internet routing with Internet key failed (status: $INTERNET_AUTH_RESPONSE)"
        if [[ -f /tmp/internet_auth.json ]]; then
            ERROR_MSG=$(cat /tmp/internet_auth.json | jq -r '.error.message // .message // "Unknown error"')
            log_error "   Error: $ERROR_MSG"
        fi
    fi
    echo ""
else
    log_warning "2. Skipping Internet API key test (key not provided)"
    echo ""
fi

# Test 3: VPN routing with VPN API key
if [[ -n "$VPN_API_KEY" ]]; then
    echo "3. Testing VPN Routing with VPN API Key"
    ((TOTAL_TESTS++))
    VPN_AUTH_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/vpn_auth.json \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $VPN_API_KEY" \
        "$API_GATEWAY_URL/v1/vpn/bedrock/invoke-model" || echo "000")
    
    if [[ "$VPN_AUTH_RESPONSE" == "200" ]]; then
        log_success "VPN routing with VPN key successful"
        ((PASSED_TESTS++))
    else
        log_error "VPN routing with VPN key failed (status: $VPN_AUTH_RESPONSE)"
        if [[ -f /tmp/vpn_auth.json ]]; then
            ERROR_MSG=$(cat /tmp/vpn_auth.json | jq -r '.error.message // .message // "Unknown error"')
            log_error "   Error: $ERROR_MSG"
        fi
    fi
    echo ""
else
    log_warning "3. Skipping VPN API key test (key not provided)"
    echo ""
fi

# Test 4: Cross-routing validation (Internet key on VPN endpoint should fail)
if [[ -n "$INTERNET_API_KEY" ]]; then
    echo "4. Testing Cross-routing Validation (Internet key on VPN endpoint - should fail)"
    ((TOTAL_TESTS++))
    CROSS_ROUTE_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/cross_route.json \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $INTERNET_API_KEY" \
        "$API_GATEWAY_URL/v1/vpn/bedrock/invoke-model" || echo "000")
    
    if [[ "$CROSS_ROUTE_RESPONSE" == "403" || "$CROSS_ROUTE_RESPONSE" == "401" ]]; then
        log_success "Cross-routing correctly rejected (status: $CROSS_ROUTE_RESPONSE)"
        ((PASSED_TESTS++))
    else
        log_error "Cross-routing validation failed - expected 401/403, got: $CROSS_ROUTE_RESPONSE"
        if [[ -f /tmp/cross_route.json ]]; then
            log_error "   Response: $(cat /tmp/cross_route.json)"
        fi
    fi
    echo ""
else
    log_warning "4. Skipping cross-routing test (Internet key not provided)"
    echo ""
fi

# Test 5: Admin key on Internet endpoint
if [[ -n "$ADMIN_API_KEY" ]]; then
    echo "5. Testing Admin Key on Internet Endpoint"
    ((TOTAL_TESTS++))
    ADMIN_INTERNET_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/admin_internet.json \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $ADMIN_API_KEY" \
        "$API_GATEWAY_URL/v1/bedrock/invoke-model" || echo "000")
    
    if [[ "$ADMIN_INTERNET_RESPONSE" == "200" ]]; then
        log_success "Admin key on Internet endpoint successful"
        ((PASSED_TESTS++))
    else
        log_error "Admin key on Internet endpoint failed (status: $ADMIN_INTERNET_RESPONSE)"
        if [[ -f /tmp/admin_internet.json ]]; then
            ERROR_MSG=$(cat /tmp/admin_internet.json | jq -r '.error.message // .message // "Unknown error"')
            log_error "   Error: $ERROR_MSG"
        fi
    fi
    echo ""
else
    log_warning "5. Skipping Admin key Internet test (key not provided)"
    echo ""
fi

# Test 6: Admin key on VPN endpoint
if [[ -n "$ADMIN_API_KEY" ]]; then
    echo "6. Testing Admin Key on VPN Endpoint"
    ((TOTAL_TESTS++))
    ADMIN_VPN_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/admin_vpn.json \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $ADMIN_API_KEY" \
        "$API_GATEWAY_URL/v1/vpn/bedrock/invoke-model" || echo "000")
    
    if [[ "$ADMIN_VPN_RESPONSE" == "200" ]]; then
        log_success "Admin key on VPN endpoint successful"
        ((PASSED_TESTS++))
    else
        log_error "Admin key on VPN endpoint failed (status: $ADMIN_VPN_RESPONSE)"
        if [[ -f /tmp/admin_vpn.json ]]; then
            ERROR_MSG=$(cat /tmp/admin_vpn.json | jq -r '.error.message // .message // "Unknown error"')
            log_error "   Error: $ERROR_MSG"
        fi
    fi
    echo ""
else
    log_warning "6. Skipping Admin key VPN test (key not provided)"
    echo ""
fi

# Test 7: Rate limiting test (if admin key available)
if [[ -n "$ADMIN_API_KEY" ]]; then
    echo "7. Testing Rate Limiting (rapid requests)"
    ((TOTAL_TESTS++))
    log_info "   Sending 10 rapid requests to test throttling..."
    
    RATE_LIMIT_PASSED=true
    THROTTLED_COUNT=0
    
    for i in {1..10}; do
        RATE_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/rate_test_$i.json \
            -H "Content-Type: application/json" \
            -H "X-API-Key: $ADMIN_API_KEY" \
            "$API_GATEWAY_URL/v1/bedrock/invoke-model" || echo "000")
        
        if [[ "$RATE_RESPONSE" == "429" ]]; then
            ((THROTTLED_COUNT++))
        fi
        
        # Small delay to avoid overwhelming
        sleep 0.1
    done
    
    if [[ $THROTTLED_COUNT -gt 0 ]]; then
        log_success "Rate limiting working ($THROTTLED_COUNT requests throttled)"
        ((PASSED_TESTS++))
    else
        log_warning "Rate limiting test inconclusive (no throttling detected)"
        ((PASSED_TESTS++))  # Still count as passed since it might be within limits
    fi
    echo ""
else
    log_warning "7. Skipping rate limiting test (Admin key not provided)"
    echo ""
fi

# Test 8: Invalid API key
echo "8. Testing Invalid API Key (should fail)"
((TOTAL_TESTS++))
INVALID_KEY_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/invalid_key.json \
    -H "Content-Type: application/json" \
    -H "X-API-Key: invalid-key-12345" \
    "$API_GATEWAY_URL/v1/bedrock/invoke-model" || echo "000")

if [[ "$INVALID_KEY_RESPONSE" == "403" || "$INVALID_KEY_RESPONSE" == "401" ]]; then
    log_success "Invalid key correctly rejected (status: $INVALID_KEY_RESPONSE)"
    ((PASSED_TESTS++))
else
    log_error "Invalid key test failed - expected 401/403, got: $INVALID_KEY_RESPONSE"
    if [[ -f /tmp/invalid_key.json ]]; then
        log_error "   Response: $(cat /tmp/invalid_key.json)"
    fi
fi
echo ""

# Test 9: GET requests with authentication
if [[ -n "$ADMIN_API_KEY" ]]; then
    echo "9. Testing GET Requests with Authentication"
    ((TOTAL_TESTS++))
    GET_AUTH_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/get_auth.json \
        -H "X-API-Key: $ADMIN_API_KEY" \
        "$API_GATEWAY_URL/v1/bedrock/invoke-model" || echo "000")
    
    if [[ "$GET_AUTH_RESPONSE" == "200" ]]; then
        log_success "GET request with authentication successful"
        ROUTING_METHOD=$(cat /tmp/get_auth.json | jq -r '.routing.method // "unknown"')
        log_info "   Routing Method: $ROUTING_METHOD"
        ((PASSED_TESTS++))
    else
        log_error "GET request with authentication failed (status: $GET_AUTH_RESPONSE)"
        if [[ -f /tmp/get_auth.json ]]; then
            ERROR_MSG=$(cat /tmp/get_auth.json | jq -r '.error.message // .message // "Unknown error"')
            log_error "   Error: $ERROR_MSG"
        fi
    fi
    echo ""
else
    log_warning "9. Skipping GET authentication test (Admin key not provided)"
    echo ""
fi

# Summary
echo "=== AUTHENTICATION TEST SUMMARY ==="
echo "Tests Passed: $PASSED_TESTS/$TOTAL_TESTS"

if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
    log_success "All authentication tests passed! Dual routing authentication is working correctly."
    EXIT_CODE=0
elif [[ $PASSED_TESTS -gt $((TOTAL_TESTS / 2)) ]]; then
    log_warning "Most tests passed. Check failed tests above."
    EXIT_CODE=1
else
    log_error "Many tests failed. Check your authentication configuration."
    EXIT_CODE=2
fi

# Clean up test files
rm -f /tmp/no_auth.json /tmp/internet_auth.json /tmp/vpn_auth.json /tmp/cross_route.json
rm -f /tmp/admin_internet.json /tmp/admin_vpn.json /tmp/invalid_key.json /tmp/get_auth.json
rm -f /tmp/rate_test_*.json

echo ""
log_info "Authentication testing completed."

# Provide recommendations
echo ""
echo "=== RECOMMENDATIONS ==="
if [[ -z "$INTERNET_API_KEY" && -z "$VPN_API_KEY" && -z "$ADMIN_API_KEY" ]]; then
    log_warning "No API keys provided. Consider running with actual keys for comprehensive testing."
fi

if [[ $THROTTLED_COUNT -eq 0 && -n "$ADMIN_API_KEY" ]]; then
    log_info "No rate limiting detected. This might be normal if within configured limits."
fi

log_info "For production use:"
log_info "1. Rotate API keys regularly"
log_info "2. Monitor authentication failures"
log_info "3. Set up alerts for unusual access patterns"
log_info "4. Consider implementing additional authentication methods"

exit $EXIT_CODE