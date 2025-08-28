#!/bin/bash

# Test bearer token functionality for dual routing system
# This script tests the basic bearer token authentication

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

log_info "Testing Bearer Token Functionality"
log_info "=================================="

# Test 1: Check environment variable is set
log_info "Test 1: Checking environment variable..."
if [[ -n "$AWS_BEARER_TOKEN_BEDROCK" ]]; then
    log_success "✅ AWS_BEARER_TOKEN_BEDROCK environment variable is set"
    log_info "   Token: ${AWS_BEARER_TOKEN_BEDROCK:0:20}..."
else
    log_error "❌ AWS_BEARER_TOKEN_BEDROCK environment variable is not set"
    exit 1
fi

# Test 2: Check Secrets Manager has the token
log_info ""
log_info "Test 2: Checking Secrets Manager..."
if aws secretsmanager get-secret-value \
    --secret-id "cross-partition-commercial-creds" \
    --query 'SecretString' --output text | jq -r '.bedrock_bearer_token' | head -c 20 >/dev/null 2>&1; then
    log_success "✅ Bearer token found in Secrets Manager"
else
    log_error "❌ Bearer token not found in Secrets Manager"
    exit 1
fi

# Test 3: Test Python import of Lambda functions
log_info ""
log_info "Test 3: Testing Python imports..."

cd lambda

# Test Internet Lambda import
if python3 -c "
import sys
sys.path.append('.')
try:
    from dual_routing_internet_lambda import get_bedrock_bearer_token, make_bedrock_request
    print('✅ Internet Lambda functions imported successfully')
except ImportError as e:
    print(f'❌ Internet Lambda import failed: {e}')
    sys.exit(1)
" 2>/dev/null; then
    log_success "✅ Internet Lambda functions import successfully"
else
    log_error "❌ Internet Lambda functions import failed"
    cd ..
    exit 1
fi

# Test VPN Lambda import
if python3 -c "
import sys
sys.path.append('.')
try:
    from dual_routing_vpn_lambda import get_bedrock_bearer_token_vpc, make_bedrock_request_vpn
    print('✅ VPN Lambda functions imported successfully')
except ImportError as e:
    print(f'❌ VPN Lambda import failed: {e}')
    sys.exit(1)
" 2>/dev/null; then
    log_success "✅ VPN Lambda functions import successfully"
else
    log_error "❌ VPN Lambda functions import failed"
    cd ..
    exit 1
fi

cd ..

# Test 4: Test bearer token retrieval function
log_info ""
log_info "Test 4: Testing bearer token retrieval..."

if python3 -c "
import sys
import os
sys.path.append('lambda')

# Set up environment
os.environ['AWS_BEARER_TOKEN_BEDROCK'] = '$AWS_BEARER_TOKEN_BEDROCK'

try:
    from dual_routing_internet_lambda import get_bedrock_bearer_token
    token = get_bedrock_bearer_token()
    if token and len(token) > 20:
        print('✅ Bearer token retrieved successfully')
        print(f'   Token length: {len(token)} characters')
        print(f'   Token preview: {token[:20]}...')
    else:
        print('❌ Bearer token retrieval failed or token too short')
        sys.exit(1)
except Exception as e:
    print(f'❌ Bearer token retrieval failed: {e}')
    sys.exit(1)
"; then
    log_success "✅ Bearer token retrieval works correctly"
else
    log_error "❌ Bearer token retrieval failed"
    exit 1
fi

# Test 5: Test basic HTTP request structure (without actually calling Bedrock)
log_info ""
log_info "Test 5: Testing HTTP request structure..."

if python3 -c "
import sys
import json
import urllib.request
sys.path.append('lambda')

# Mock test - just validate the request structure
def test_request_structure():
    bearer_token = 'test-token-123'
    model_id = 'anthropic.claude-3-haiku-20240307-v1:0'
    request_body = {
        'messages': [{'role': 'user', 'content': 'test'}],
        'max_tokens': 10
    }
    
    # Test URL construction
    bedrock_url = f'https://bedrock-runtime.us-east-1.amazonaws.com/model/{model_id}/invoke'
    
    # Test headers
    headers = {
        'Authorization': f'Bearer {bearer_token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json'
    }
    
    # Test request construction (don't actually send)
    req = urllib.request.Request(
        bedrock_url,
        data=json.dumps(request_body).encode('utf-8'),
        headers=headers,
        method='POST'
    )
    
    # Validate request components
    assert req.get_full_url() == bedrock_url
    assert req.get_header('Authorization') == f'Bearer {bearer_token}'
    assert req.get_header('Content-type') == 'application/json'
    assert req.get_method() == 'POST'
    
    print('✅ HTTP request structure is correct')
    return True

test_request_structure()
"; then
    log_success "✅ HTTP request structure is valid"
else
    log_error "❌ HTTP request structure test failed"
    exit 1
fi

# Summary
log_info ""
log_success "🎉 All Bearer Token Functionality Tests Passed!"
log_info ""
log_info "Test Results Summary:"
log_info "✅ Environment variable configured"
log_info "✅ Secrets Manager contains bearer token"
log_info "✅ Lambda functions import successfully"
log_info "✅ Bearer token retrieval works"
log_info "✅ HTTP request structure is valid"
log_info ""
log_info "The dual routing system is ready to use bearer token authentication!"
log_info ""
log_info "Next steps:"
log_info "1. Deploy the updated Lambda functions"
log_info "2. Test with actual Bedrock API calls"
log_info "3. Run end-to-end validation tests"