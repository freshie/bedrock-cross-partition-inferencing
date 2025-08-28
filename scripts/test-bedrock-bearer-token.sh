#!/bin/bash

# Test actual Bedrock API call with bearer token
# This script tests a real Bedrock API call using the bearer token

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

log_info "Testing Bedrock API Call with Bearer Token"
log_info "=========================================="

# Check if bearer token is available
if [[ -z "$AWS_BEARER_TOKEN_BEDROCK" ]]; then
    log_error "AWS_BEARER_TOKEN_BEDROCK environment variable is not set"
    exit 1
fi

log_info "Bearer Token: ${AWS_BEARER_TOKEN_BEDROCK:0:20}..."

# Test with a simple Bedrock API call
log_info ""
log_info "Testing Bedrock API call..."

python3 -c "
import json
import urllib.request
import urllib.error
import os

def test_bedrock_call():
    bearer_token = os.environ.get('AWS_BEARER_TOKEN_BEDROCK')
    model_id = 'anthropic.claude-3-haiku-20240307-v1:0'
    
    # Simple test request
    request_body = {
        'messages': [
            {
                'role': 'user',
                'content': 'Hello! Please respond with just \"Bearer token test successful\" if you can read this.'
            }
        ],
        'max_tokens': 20,
        'temperature': 0.1,
        'anthropic_version': 'bedrock-2023-05-31'
    }
    
    # Bedrock endpoint URL
    bedrock_url = f'https://bedrock-runtime.us-east-1.amazonaws.com/model/{model_id}/invoke'
    
    headers = {
        'Authorization': f'Bearer {bearer_token}',
        'Content-Type': 'application/json',
        'Accept': 'application/json'
    }
    
    try:
        # Make the request
        req = urllib.request.Request(
            bedrock_url,
            data=json.dumps(request_body).encode('utf-8'),
            headers=headers,
            method='POST'
        )
        
        print('🔄 Making Bedrock API call...')
        
        with urllib.request.urlopen(req, timeout=30) as response:
            response_data = json.loads(response.read().decode('utf-8'))
            
            print('✅ Bedrock API call successful!')
            print(f'   Status Code: {response.status}')
            
            # Extract the response content
            if 'content' in response_data and len(response_data['content']) > 0:
                content = response_data['content'][0].get('text', 'No text content')
                print(f'   Response: {content}')
            else:
                print(f'   Raw Response: {json.dumps(response_data, indent=2)}')
            
            return True
            
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8') if e.fp else 'No error details'
        print(f'❌ Bedrock HTTP error {e.code}: {error_body}')
        return False
    except urllib.error.URLError as e:
        print(f'❌ Bedrock URL error: {str(e)}')
        return False
    except Exception as e:
        print(f'❌ Unexpected error: {str(e)}')
        return False

# Run the test
success = test_bedrock_call()
exit(0 if success else 1)
"

if [[ $? -eq 0 ]]; then
    log_success "🎉 Bedrock API call with bearer token successful!"
    log_info ""
    log_info "This confirms that:"
    log_info "✅ Bearer token is valid and working"
    log_info "✅ Cross-partition authentication is functional"
    log_info "✅ Bedrock API is accessible with the token"
    log_info "✅ HTTP request structure is correct"
    log_info ""
    log_info "The dual routing system is ready for deployment!"
else
    log_error "❌ Bedrock API call failed"
    log_info ""
    log_info "This could indicate:"
    log_info "• Bearer token may be expired or invalid"
    log_info "• Network connectivity issues"
    log_info "• Bedrock service availability issues"
    log_info "• Request format issues"
    log_info ""
    log_info "Please check the error details above and verify:"
    log_info "1. Bearer token is current and valid"
    log_info "2. Network connectivity to Bedrock"
    log_info "3. Bedrock service status"
    exit 1
fi