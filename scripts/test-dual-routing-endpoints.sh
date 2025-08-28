#!/bin/bash

# Test script for dual routing API Gateway endpoints
# Tests both internet and VPN routing paths

set -e

# Default values
API_GATEWAY_URL=""
API_KEY=""
TEST_MODEL="anthropic.claude-3-haiku-20240307-v1:0"
TEST_PROMPT="Hello, this is a test message for dual routing validation."

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
Test dual routing API Gateway endpoints

Usage: $0 [OPTIONS]

Options:
    --api-url URL               API Gateway base URL (required)
    --api-key KEY              API key for authentication (optional)
    --test-model MODEL         Model ID to test (default: anthropic.claude-3-haiku-20240307-v1:0)
    --test-prompt PROMPT       Test prompt (default: test message)
    --help                     Show this help message

Examples:
    # Test with API key
    $0 --api-url https://YOUR-API-ID.execute-api.us-gov-west-1.amazonaws.com/prod \\
       --api-key your-api-key-here
    
    # Test without API key (if not required)
    $0 --api-url https://YOUR-API-ID.execute-api.us-gov-west-1.amazonaws.com/prod

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --api-url)
            API_GATEWAY_URL="$2"
            shift 2
            ;;
        --api-key)
            API_KEY="$2"
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

log_info "Starting dual routing endpoint tests..."
log_info "  API Gateway URL: $API_GATEWAY_URL"
log_info "  Test Model: $TEST_MODEL"
log_info "  API Key: ${API_KEY:+[PROVIDED]}${API_KEY:-[NOT PROVIDED]}"

# Prepare headers
HEADERS=(-H "Content-Type: application/json")
if [[ -n "$API_KEY" ]]; then
    HEADERS+=(-H "X-API-Key: $API_KEY")
fi

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
        "max_tokens": 100,
        "temperature": 0.7
    }
}
EOF
)

echo "=== DUAL ROUTING ENDPOINT TESTS ==="
echo ""

# Test 1: Internet Routing - GET (Info)
echo "1. Testing Internet Routing - GET (Info)"
echo "   Endpoint: $API_GATEWAY_URL/v1/bedrock/invoke-model"
INTERNET_GET_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/internet_get.json "${HEADERS[@]}" "$API_GATEWAY_URL/v1/bedrock/invoke-model" || echo "000")
if [[ "$INTERNET_GET_RESPONSE" == "200" ]]; then
    log_success "Internet GET test successful"
    ROUTING_METHOD=$(cat /tmp/internet_get.json | jq -r '.routing.method // "unknown"')
    MESSAGE=$(cat /tmp/internet_get.json | jq -r '.message // "No message"')
    log_info "   Routing Method: $ROUTING_METHOD"
    log_info "   Message: $MESSAGE"
else
    log_error "Internet GET test failed with status: $INTERNET_GET_RESPONSE"
    if [[ -f /tmp/internet_get.json ]]; then
        log_error "   Response: $(cat /tmp/internet_get.json)"
    fi
fi
echo ""

# Test 2: VPN Routing - GET (Info)
echo "2. Testing VPN Routing - GET (Info)"
echo "   Endpoint: $API_GATEWAY_URL/v1/vpn/bedrock/invoke-model"
VPN_GET_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/vpn_get.json "${HEADERS[@]}" "$API_GATEWAY_URL/v1/vpn/bedrock/invoke-model" || echo "000")
if [[ "$VPN_GET_RESPONSE" == "200" ]]; then
    log_success "VPN GET test successful"
    ROUTING_METHOD=$(cat /tmp/vpn_get.json | jq -r '.routing.method // "unknown"')
    MESSAGE=$(cat /tmp/vpn_get.json | jq -r '.message // "No message"')
    log_info "   Routing Method: $ROUTING_METHOD"
    log_info "   Message: $MESSAGE"
else
    log_error "VPN GET test failed with status: $VPN_GET_RESPONSE"
    if [[ -f /tmp/vpn_get.json ]]; then
        log_error "   Response: $(cat /tmp/vpn_get.json)"
    fi
fi
echo ""

# Test 3: Internet Routing - Models List
echo "3. Testing Internet Routing - Models List"
echo "   Endpoint: $API_GATEWAY_URL/v1/bedrock/models"
INTERNET_MODELS_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/internet_models.json "${HEADERS[@]}" "$API_GATEWAY_URL/v1/bedrock/models" || echo "000")
if [[ "$INTERNET_MODELS_RESPONSE" == "200" ]]; then
    log_success "Internet models test successful"
    MODEL_COUNT=$(cat /tmp/internet_models.json | jq -r '.totalModels // 0')
    ROUTING_METHOD=$(cat /tmp/internet_models.json | jq -r '.source.routing_method // "unknown"')
    log_info "   Routing Method: $ROUTING_METHOD"
    log_info "   Models Found: $MODEL_COUNT"
else
    log_error "Internet models test failed with status: $INTERNET_MODELS_RESPONSE"
    if [[ -f /tmp/internet_models.json ]]; then
        log_error "   Response: $(cat /tmp/internet_models.json)"
    fi
fi
echo ""

# Test 4: VPN Routing - Models List
echo "4. Testing VPN Routing - Models List"
echo "   Endpoint: $API_GATEWAY_URL/v1/vpn/bedrock/models"
VPN_MODELS_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/vpn_models.json "${HEADERS[@]}" "$API_GATEWAY_URL/v1/vpn/bedrock/models" || echo "000")
if [[ "$VPN_MODELS_RESPONSE" == "200" ]]; then
    log_success "VPN models test successful"
    MODEL_COUNT=$(cat /tmp/vpn_models.json | jq -r '.totalModels // 0')
    ROUTING_METHOD=$(cat /tmp/vpn_models.json | jq -r '.source.routing_method // "unknown"')
    log_info "   Routing Method: $ROUTING_METHOD"
    log_info "   Models Found: $MODEL_COUNT"
else
    log_error "VPN models test failed with status: $VPN_MODELS_RESPONSE"
    if [[ -f /tmp/vpn_models.json ]]; then
        log_error "   Response: $(cat /tmp/vpn_models.json)"
    fi
fi
echo ""

# Test 5: Internet Routing - POST (Inference)
echo "5. Testing Internet Routing - POST (Inference)"
echo "   Endpoint: $API_GATEWAY_URL/v1/bedrock/invoke-model"
echo "   Model: $TEST_MODEL"
INTERNET_POST_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/internet_post.json "${HEADERS[@]}" -d "$TEST_PAYLOAD" "$API_GATEWAY_URL/v1/bedrock/invoke-model" || echo "000")
if [[ "$INTERNET_POST_RESPONSE" == "200" ]]; then
    log_success "Internet POST test successful"
    ROUTING_METHOD=$(cat /tmp/internet_post.json | jq -r '.routing_method // "unknown"')
    RESPONSE_BODY=$(cat /tmp/internet_post.json | jq -r '.body // "No response body"')
    log_info "   Routing Method: $ROUTING_METHOD"
    log_info "   Response Length: ${#RESPONSE_BODY} characters"
else
    log_error "Internet POST test failed with status: $INTERNET_POST_RESPONSE"
    if [[ -f /tmp/internet_post.json ]]; then
        ERROR_MSG=$(cat /tmp/internet_post.json | jq -r '.error.message // .message // "Unknown error"')
        log_error "   Error: $ERROR_MSG"
    fi
fi
echo ""

# Test 6: VPN Routing - POST (Inference)
echo "6. Testing VPN Routing - POST (Inference)"
echo "   Endpoint: $API_GATEWAY_URL/v1/vpn/bedrock/invoke-model"
echo "   Model: $TEST_MODEL"
VPN_POST_RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/vpn_post.json "${HEADERS[@]}" -d "$TEST_PAYLOAD" "$API_GATEWAY_URL/v1/vpn/bedrock/invoke-model" || echo "000")
if [[ "$VPN_POST_RESPONSE" == "200" ]]; then
    log_success "VPN POST test successful"
    ROUTING_METHOD=$(cat /tmp/vpn_post.json | jq -r '.routing_method // "unknown"')
    RESPONSE_BODY=$(cat /tmp/vpn_post.json | jq -r '.body // "No response body"')
    log_info "   Routing Method: $ROUTING_METHOD"
    log_info "   Response Length: ${#RESPONSE_BODY} characters"
else
    log_error "VPN POST test failed with status: $VPN_POST_RESPONSE"
    if [[ -f /tmp/vpn_post.json ]]; then
        ERROR_MSG=$(cat /tmp/vpn_post.json | jq -r '.error.message // .message // "Unknown error"')
        log_error "   Error: $ERROR_MSG"
    fi
fi
echo ""

# Test 7: Cross-routing validation (Internet Lambda should reject VPN paths)
echo "7. Testing Cross-routing Validation"
echo "   Testing if Internet Lambda properly rejects VPN paths..."
# This test would require calling the Internet Lambda directly with a VPN path
# For now, we'll skip this as it requires direct Lambda invocation
log_info "   Cross-routing validation requires direct Lambda testing"
echo ""

# Summary
echo "=== TEST SUMMARY ==="
TOTAL_TESTS=6
PASSED_TESTS=0

[[ "$INTERNET_GET_RESPONSE" == "200" ]] && ((PASSED_TESTS++))
[[ "$VPN_GET_RESPONSE" == "200" ]] && ((PASSED_TESTS++))
[[ "$INTERNET_MODELS_RESPONSE" == "200" ]] && ((PASSED_TESTS++))
[[ "$VPN_MODELS_RESPONSE" == "200" ]] && ((PASSED_TESTS++))
[[ "$INTERNET_POST_RESPONSE" == "200" ]] && ((PASSED_TESTS++))
[[ "$VPN_POST_RESPONSE" == "200" ]] && ((PASSED_TESTS++))

echo "Tests Passed: $PASSED_TESTS/$TOTAL_TESTS"

if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
    log_success "All tests passed! Dual routing is working correctly."
    EXIT_CODE=0
elif [[ $PASSED_TESTS -gt 0 ]]; then
    log_warning "Some tests passed. Check failed tests above."
    EXIT_CODE=1
else
    log_error "All tests failed. Check your configuration."
    EXIT_CODE=2
fi

# Clean up test files
rm -f /tmp/internet_get.json /tmp/vpn_get.json /tmp/internet_models.json /tmp/vpn_models.json /tmp/internet_post.json /tmp/vpn_post.json

echo ""
log_info "Dual routing endpoint testing completed."

exit $EXIT_CODE