import json
import sys
import os
sys.path.append(os.path.dirname(__file__))
from lambda_function import parse_request

def test_parse_request():
    """Test request parsing from API Gateway event"""
    event = {
        'body': json.dumps({
            'modelId': 'anthropic.claude-3-sonnet-20240229-v1:0',
            'contentType': 'application/json',
            'accept': 'application/json',
            'body': '{"messages": [{"role": "user", "content": "Hello"}]}'
        }),
        'requestContext': {
            'identity': {
                'sourceIp': '192.168.1.1',
                'userArn': 'arn:aws-us-gov:iam::123456789012:user/testuser'
            }
        }
    }
    
    result = parse_request(event)
    
    assert result['modelId'] == 'anthropic.claude-3-sonnet-20240229-v1:0'
    assert result['contentType'] == 'application/json'
    assert result['sourceIP'] == '192.168.1.1'
    assert result['userArn'] == 'arn:aws-us-gov:iam::123456789012:user/testuser'

def test_parse_request_missing_model():
    """Test request parsing with missing modelId"""
    event = {
        'body': json.dumps({
            'contentType': 'application/json',
            'body': '{"messages": []}'
        })
    }
    
    try:
        parse_request(event)
        return False  # Should have raised an exception
    except ValueError as e:
        return "Missing required parameter: modelId" in str(e)

if __name__ == '__main__':
    # Run basic tests
    print("Running basic Lambda function tests...")
    
    # Test request parsing
    try:
        test_parse_request()
        print("✅ Request parsing test passed")
    except Exception as e:
        print(f"❌ Request parsing test failed: {e}")
    
    # Test missing model validation
    if test_parse_request_missing_model():
        print("✅ Missing model validation test passed")
    else:
        print("❌ Missing model validation test failed")
    
    print("Basic tests completed!")