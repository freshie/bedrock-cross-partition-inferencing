#!/bin/bash

# Test Lambda functions with bearer token authentication
# This script tests the Lambda functions directly

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

log_info "Testing Lambda Functions with Bearer Token"
log_info "========================================="

# Check if bearer token is available
if [[ -z "$AWS_BEARER_TOKEN_BEDROCK" ]]; then
    log_error "AWS_BEARER_TOKEN_BEDROCK environment variable is not set"
    exit 1
fi

# Test Internet Lambda function
log_info ""
log_info "Test 1: Testing Internet Lambda function..."

cd lambda

python3 -c "
import json
import os
import sys
import uuid
from unittest.mock import Mock, patch

# Set up environment
os.environ['AWS_BEARER_TOKEN_BEDROCK'] = '$AWS_BEARER_TOKEN_BEDROCK'
os.environ['COMMERCIAL_CREDENTIALS_SECRET'] = 'test-secret'
os.environ['REQUEST_LOG_TABLE'] = 'test-table'

# Mock AWS clients
with patch('dual_routing_internet_lambda.secrets_client'), \
     patch('dual_routing_internet_lambda.dynamodb'), \
     patch('dual_routing_internet_lambda.log_request'), \
     patch('dual_routing_internet_lambda.send_custom_metrics'):
    
    from dual_routing_internet_lambda import lambda_handler
    
    # Create test event
    event = {
        'path': '/v1/bedrock/invoke-model',
        'httpMethod': 'POST',
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps({
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'body': {
                'messages': [
                    {
                        'role': 'user',
                        'content': 'Test message for Internet Lambda with bearer token'
                    }
                ],
                'max_tokens': 50,
                'temperature': 0.5,
                'anthropic_version': 'bedrock-2023-05-31'
            }
        })
    }
    
    # Create test context
    context = Mock()
    context.aws_request_id = str(uuid.uuid4())
    
    try:
        print('🔄 Testing Internet Lambda handler...')
        result = lambda_handler(event, context)
        
        if result['statusCode'] == 200:
            print('✅ Internet Lambda test successful!')
            body = json.loads(result['body'])
            if 'content' in body:
                print(f'   Response received from Bedrock')
                print(f'   Routing method: {body.get(\"routing_method\", \"unknown\")}')
            else:
                print(f'   Response: {json.dumps(body, indent=2)[:200]}...')
        else:
            print(f'❌ Internet Lambda test failed with status {result[\"statusCode\"]}')
            print(f'   Error: {result.get(\"body\", \"No error details\")}')
            sys.exit(1)
            
    except Exception as e:
        print(f'❌ Internet Lambda test failed with exception: {str(e)}')
        sys.exit(1)
"

if [[ $? -eq 0 ]]; then
    log_success "✅ Internet Lambda function test passed"
else
    log_error "❌ Internet Lambda function test failed"
    cd ..
    exit 1
fi

# Test VPN Lambda function (without actual VPC)
log_info ""
log_info "Test 2: Testing VPN Lambda function (bearer token retrieval only)..."

python3 -c "
import json
import os
import sys
from unittest.mock import Mock, patch

# Set up environment
os.environ['AWS_BEARER_TOKEN_BEDROCK'] = '$AWS_BEARER_TOKEN_BEDROCK'
os.environ['COMMERCIAL_CREDENTIALS_SECRET'] = 'test-secret'
os.environ['REQUEST_LOG_TABLE'] = 'test-table'

try:
    from dual_routing_vpn_lambda import get_bedrock_bearer_token_vpc
    
    print('🔄 Testing VPN Lambda bearer token retrieval...')
    token = get_bedrock_bearer_token_vpc()
    
    if token and len(token) > 20:
        print('✅ VPN Lambda bearer token retrieval successful!')
        print(f'   Token length: {len(token)} characters')
        print(f'   Token preview: {token[:20]}...')
    else:
        print('❌ VPN Lambda bearer token retrieval failed')
        sys.exit(1)
        
except Exception as e:
    print(f'❌ VPN Lambda test failed: {str(e)}')
    sys.exit(1)
"

if [[ $? -eq 0 ]]; then
    log_success "✅ VPN Lambda bearer token test passed"
else
    log_error "❌ VPN Lambda bearer token test failed"
    cd ..
    exit 1
fi

cd ..

# Test the make_bedrock_request function directly
log_info ""
log_info "Test 3: Testing make_bedrock_request function..."

python3 -c "
import json
import os
import sys
sys.path.append('lambda')

# Set up environment
os.environ['AWS_BEARER_TOKEN_BEDROCK'] = '$AWS_BEARER_TOKEN_BEDROCK'

try:
    from dual_routing_internet_lambda import make_bedrock_request, get_bedrock_bearer_token
    
    print('🔄 Testing make_bedrock_request function...')
    
    bearer_token = get_bedrock_bearer_token()
    model_id = 'anthropic.claude-3-haiku-20240307-v1:0'
    request_body = {
        'messages': [
            {
                'role': 'user',
                'content': 'Test direct function call with bearer token'
            }
        ],
        'max_tokens': 30,
        'temperature': 0.3,
        'anthropic_version': 'bedrock-2023-05-31'
    }
    
    response = make_bedrock_request(bearer_token, model_id, request_body)
    
    if 'content' in response and len(response['content']) > 0:
        print('✅ make_bedrock_request function test successful!')
        content = response['content'][0].get('text', 'No text content')
        print(f'   Response: {content}')
    else:
        print('❌ make_bedrock_request function test failed - no content in response')
        print(f'   Response: {json.dumps(response, indent=2)}')
        sys.exit(1)
        
except Exception as e:
    print(f'❌ make_bedrock_request function test failed: {str(e)}')
    sys.exit(1)
"

if [[ $? -eq 0 ]]; then
    log_success "✅ make_bedrock_request function test passed"
else
    log_error "❌ make_bedrock_request function test failed"
    exit 1
fi

# Summary
log_info ""
log_success "🎉 All Lambda Function Bearer Token Tests Passed!"
log_info ""
log_info "Test Results Summary:"
log_info "✅ Internet Lambda function works with bearer token"
log_info "✅ VPN Lambda bearer token retrieval works"
log_info "✅ make_bedrock_request function works correctly"
log_info "✅ Bearer token authentication is fully functional"
log_info ""
log_info "The Lambda functions are ready for deployment with bearer token authentication!"