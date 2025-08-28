"""
Unit tests for VPN Lambda function
Tests VPN-specific functionality, error handling, and edge cases
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
import json
import os
import sys
from datetime import datetime

# Add lambda directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lambda'))

# Import the modules to test
from dual_routing_vpn_lambda import (
    lambda_handler, detect_routing_method, parse_request,
    get_bedrock_bearer_token_vpc, forward_to_bedrock_vpn,
    get_inference_profile_id, VPCEndpointClients
)
from dual_routing_error_handler import (
    VPNError, NetworkError, AuthenticationError, ValidationError
)

class TestVPNLambdaFunction(unittest.TestCase):
    """Test cases for VPN Lambda function"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'VPC_ENDPOINT_SECRETS': 'https://vpce-secrets.us-gov-west-1.vpce.amazonaws.com',
            'VPC_ENDPOINT_DYNAMODB': 'https://vpce-dynamodb.us-gov-west-1.vpce.amazonaws.com',
            'VPC_ENDPOINT_LOGS': 'https://vpce-logs.us-gov-west-1.vpce.amazonaws.com',
            'VPC_ENDPOINT_MONITORING': 'https://vpce-monitoring.us-gov-west-1.vpce.amazonaws.com',
            'COMMERCIAL_BEDROCK_ENDPOINT': 'https://bedrock-runtime.us-east-1.amazonaws.com',
            'COMMERCIAL_CREDENTIALS_SECRET': 'test-commercial-creds',
            'REQUEST_LOG_TABLE': 'test-request-log-table',
            'ROUTING_METHOD': 'vpn'
        })
        self.env_patcher.start()
        
        # Sample API Gateway event for VPN routing
        self.vpn_event = {
            'httpMethod': 'POST',
            'path': '/v1/vpn/bedrock/invoke-model',
            'headers': {
                'Content-Type': 'application/json',
                'X-API-Key': 'test-api-key'
            },
            'body': json.dumps({
                'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                'body': {
                    'messages': [
                        {'role': 'user', 'content': 'Test message'}
                    ],
                    'max_tokens': 100
                }
            }),
            'requestContext': {
                'identity': {
                    'sourceIp': '10.0.0.1',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/testuser'
                }
            }
        }
        
        # Sample context
        self.context = Mock()
        self.context.aws_request_id = 'test-request-id'
        self.context.function_name = 'test-vpn-lambda'
        
        # Mock VPC clients
        self.vpc_clients_patcher = patch('dual_routing_vpn_lambda.vpc_clients')
        self.mock_vpc_clients = self.vpc_clients_patcher.start()
        self.mock_vpc_clients.get_health_status.return_value = {
            'secrets': {'healthy': True},
            'dynamodb': {'healthy': True},
            'cloudwatch': {'healthy': True},
            'vpn_tunnel': {'healthy': True}
        }
        self.mock_vpc_clients.validate_vpn_connectivity.return_value = None
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
        self.vpc_clients_patcher.stop()
    
    def test_detect_routing_method_vpn_path(self):
        """Test routing method detection for VPN paths"""
        vpn_paths = [
            '/v1/vpn/bedrock/invoke-model',
            '/v1/vpn/bedrock/models',
            '/prod/v1/vpn/bedrock/invoke-model'
        ]
        
        for path in vpn_paths:
            with self.subTest(path=path):
                result = detect_routing_method(path)
                self.assertEqual(result, 'vpn')
    
    def test_detect_routing_method_internet_path(self):
        """Test routing method detection for internet paths"""
        internet_paths = [
            '/v1/bedrock/invoke-model',
            '/v1/bedrock/models',
            '/prod/v1/bedrock/invoke-model'
        ]
        
        for path in internet_paths:
            with self.subTest(path=path):
                result = detect_routing_method(path)
                self.assertEqual(result, 'internet')
    
    def test_parse_request_valid_vpn_request(self):
        """Test parsing valid VPN request"""
        result = parse_request(self.vpn_event)
        
        self.assertEqual(result['modelId'], 'anthropic.claude-3-haiku-20240307-v1:0')
        self.assertEqual(result['contentType'], 'application/json')
        self.assertEqual(result['sourceIP'], '10.0.0.1')
        self.assertEqual(result['routing_method'], 'vpn')
        self.assertIn('body', result)
    
    def test_parse_request_missing_model_id(self):
        """Test parsing request with missing modelId"""
        invalid_event = self.vpn_event.copy()
        body = json.loads(invalid_event['body'])
        del body['modelId']
        invalid_event['body'] = json.dumps(body)
        
        with self.assertRaises(ValueError) as context:
            parse_request(invalid_event)
        
        self.assertIn('Missing required parameter: modelId', str(context.exception))
    
    def test_parse_request_invalid_json(self):
        """Test parsing request with invalid JSON body"""
        invalid_event = self.vpn_event.copy()
        invalid_event['body'] = 'invalid-json'
        
        with self.assertRaises(ValueError) as context:
            parse_request(invalid_event)
        
        self.assertIn('Invalid request format', str(context.exception))
    
    @patch('dual_routing_vpn_lambda.vpc_clients')
    def test_get_bedrock_bearer_token_vpc_success(self, mock_vpc_clients):
        """Test successful bearer token retrieval via VPC endpoint"""
        # Mock secrets client
        mock_secrets_client = Mock()
        mock_vpc_clients.get_secrets_client.return_value = mock_secrets_client
        
        # Mock successful response
        mock_response = {
            'SecretString': json.dumps({
                'bedrock_api_key': 'test-api-key-12345',
                'region': 'us-east-1'
            })
        }
        mock_secrets_client.get_secret_value.return_value = mock_response
        
        result = get_bedrock_bearer_token_vpc()
        
        self.assertEqual(result['bedrock_api_key'], 'test-api-key-12345')
        self.assertEqual(result['region'], 'us-east-1')
        mock_secrets_client.get_secret_value.assert_called_once()
    
    @patch('dual_routing_vpn_lambda.vpc_clients')
    def test_get_bedrock_bearer_token_vpc_failure(self, mock_vpc_clients):
        """Test bearer token retrieval failure via VPC endpoint"""
        # Mock secrets client
        mock_secrets_client = Mock()
        mock_vpc_clients.get_secrets_client.return_value = mock_secrets_client
        
        # Mock ClientError
        from botocore.exceptions import ClientError
        mock_secrets_client.get_secret_value.side_effect = ClientError(
            {'Error': {'Code': 'ResourceNotFoundException'}}, 'GetSecretValue'
        )
        
        with self.assertRaises(Exception) as context:
            get_bedrock_bearer_token_vpc()
        
        self.assertIn('Unable to retrieve commercial credentials', str(context.exception))
    
    def test_get_inference_profile_id_claude_model(self):
        """Test inference profile ID retrieval for Claude models"""
        test_cases = [
            ('anthropic.claude-3-haiku-20240307-v1:0', 'us.anthropic.claude-3-haiku-20240307-v1:0'),
            ('anthropic.claude-3-sonnet-20240229-v1:0', 'us.anthropic.claude-3-sonnet-20240229-v1:0'),
            ('unknown-model-id', None)
        ]
        
        for model_id, expected_profile in test_cases:
            with self.subTest(model_id=model_id):
                result = get_inference_profile_id(model_id)
                self.assertEqual(result, expected_profile)
    
    @patch('dual_routing_vpn_lambda.urllib.request.urlopen')
    def test_forward_to_bedrock_vpn_api_key_success(self, mock_urlopen):
        """Test successful VPN routing with API key"""
        # Mock successful HTTP response
        mock_response = Mock()
        mock_response.read.return_value = json.dumps({
            'content': [{'text': 'Test response from Bedrock'}]
        }).encode('utf-8')
        mock_response.headers = {'content-type': 'application/json'}
        mock_urlopen.return_value.__enter__.return_value = mock_response
        
        commercial_creds = {'bedrock_api_key': 'test-api-key'}
        request_data = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'body': {'messages': [{'role': 'user', 'content': 'test'}]}
        }
        
        result = forward_to_bedrock_vpn(commercial_creds, request_data)
        
        self.assertIn('body', result)
        self.assertEqual(result['routing_method'], 'vpn')
        self.assertIn('endpoint_used', result)
    
    @patch('dual_routing_vpn_lambda.urllib.request.urlopen')
    def test_forward_to_bedrock_vpn_api_key_http_error(self, mock_urlopen):
        """Test VPN routing with API key HTTP error"""
        from urllib.error import HTTPError
        
        # Mock HTTP error
        mock_urlopen.side_effect = HTTPError(
            url='test-url', code=403, msg='Forbidden', hdrs={}, fp=Mock()
        )
        mock_urlopen.side_effect.read.return_value = b'Access denied'
        
        commercial_creds = {'bedrock_api_key': 'invalid-api-key'}
        request_data = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'body': {'messages': [{'role': 'user', 'content': 'test'}]}
        }
        
        with self.assertRaises(Exception) as context:
            forward_to_bedrock_vpn(commercial_creds, request_data)
        
        self.assertIn('Access denied', str(context.exception))
    
    @patch('dual_routing_vpn_lambda.urllib.request.urlopen')
    def test_forward_to_bedrock_vpn_timeout_error(self, mock_urlopen):
        """Test VPN routing with timeout error"""
        from urllib.error import URLError
        
        # Mock timeout error
        mock_urlopen.side_effect = URLError('timeout')
        
        commercial_creds = {'bedrock_api_key': 'test-api-key'}
        request_data = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'body': {'messages': [{'role': 'user', 'content': 'test'}]}
        }
        
        with self.assertRaises(Exception) as context:
            forward_to_bedrock_vpn(commercial_creds, request_data)
        
        self.assertIn('timeout', str(context.exception))
    
    @patch('dual_routing_vpn_lambda.boto3.Session')
    def test_forward_to_bedrock_vpn_aws_credentials_success(self, mock_session):
        """Test successful VPN routing with AWS credentials"""
        # Mock AWS session and Bedrock client
        mock_bedrock_client = Mock()
        mock_session.return_value.client.return_value = mock_bedrock_client
        
        # Mock successful Bedrock response
        mock_response = Mock()
        mock_response.__getitem__.return_value.read.return_value = json.dumps({
            'content': [{'text': 'Test response'}]
        }).encode('utf-8')
        mock_bedrock_client.invoke_model.return_value = {
            'body': mock_response['body'],
            'contentType': 'application/json'
        }
        
        commercial_creds = {
            'aws_access_key_id': 'test-access-key',
            'aws_secret_access_key': 'test-secret-key',
            'region': 'us-east-1'
        }
        request_data = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'body': json.dumps({'messages': [{'role': 'user', 'content': 'test'}]})
        }
        
        result = forward_to_bedrock_vpn(commercial_creds, request_data)
        
        self.assertEqual(result['routing_method'], 'vpn')
        self.assertTrue(result['aws_credentials_used'])
    
    def test_vpc_endpoint_clients_singleton(self):
        """Test VPCEndpointClients singleton pattern"""
        client1 = VPCEndpointClients()
        client2 = VPCEndpointClients()
        
        self.assertIs(client1, client2)
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_vpc_endpoint_health_check_success(self, mock_socket):
        """Test VPC endpoint health check success"""
        # Mock successful connection
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 0  # Success
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.check_vpc_endpoint_health(
            'test-endpoint', 
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com'
        )
        
        self.assertTrue(result)
        self.assertTrue(vpc_clients._health_status['test-endpoint']['healthy'])
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_vpc_endpoint_health_check_failure(self, mock_socket):
        """Test VPC endpoint health check failure"""
        # Mock failed connection
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 1  # Connection failed
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.check_vpc_endpoint_health(
            'test-endpoint', 
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com'
        )
        
        self.assertFalse(result)
        self.assertFalse(vpc_clients._health_status['test-endpoint']['healthy'])
    
    @patch('dual_routing_vpn_lambda.log_request_vpc')
    @patch('dual_routing_vpn_lambda.send_custom_metrics')
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_vpn_enhanced')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials_vpc_with_retry')
    def test_lambda_handler_successful_vpn_request(self, mock_get_creds, mock_forward, 
                                                   mock_metrics, mock_log):
        """Test successful VPN Lambda handler execution"""
        # Mock successful credential retrieval
        mock_get_creds.return_value = {'bedrock_api_key': 'test-key'}
        
        # Mock successful Bedrock forwarding
        mock_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'Test response'}]}),
            'contentType': 'application/json'
        }
        
        result = lambda_handler(self.vpn_event, self.context)
        
        self.assertEqual(result['statusCode'], 200)
        self.assertIn('X-Routing-Method', result['headers'])
        self.assertEqual(result['headers']['X-Routing-Method'], 'vpn')
        
        # Verify mocks were called
        mock_get_creds.assert_called_once()
        mock_forward.assert_called_once()
        mock_metrics.assert_called_once()
        mock_log.assert_called_once()
    
    def test_lambda_handler_invalid_routing_path(self):
        """Test Lambda handler with invalid routing path"""
        # Create event with internet path (should be rejected by VPN Lambda)
        internet_event = self.vpn_event.copy()
        internet_event['path'] = '/v1/bedrock/invoke-model'
        
        result = lambda_handler(internet_event, self.context)
        
        self.assertEqual(result['statusCode'], 400)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VALIDATION_ERROR')
        self.assertIn('internet routing requests', body['error']['message'])
    
    def test_lambda_handler_get_request_routing_info(self):
        """Test Lambda handler GET request for routing info"""
        get_event = self.vpn_event.copy()
        get_event['httpMethod'] = 'GET'
        
        with patch('dual_routing_vpn_lambda.get_routing_info') as mock_get_info:
            mock_get_info.return_value = {
                'statusCode': 200,
                'body': json.dumps({'message': 'VPN routing info'})
            }
            
            result = lambda_handler(get_event, self.context)
            
            self.assertEqual(result['statusCode'], 200)
            mock_get_info.assert_called_once()
    
    def test_lambda_handler_get_request_models(self):
        """Test Lambda handler GET request for models"""
        get_event = self.vpn_event.copy()
        get_event['httpMethod'] = 'GET'
        get_event['path'] = '/v1/vpn/bedrock/models'
        
        with patch('dual_routing_vpn_lambda.get_available_models') as mock_get_models:
            mock_get_models.return_value = {
                'statusCode': 200,
                'body': json.dumps({'models': []})
            }
            
            result = lambda_handler(get_event, self.context)
            
            self.assertEqual(result['statusCode'], 200)
            mock_get_models.assert_called_once()
    
    @patch('dual_routing_vpn_lambda.get_commercial_credentials_vpc_with_retry')
    def test_lambda_handler_vpn_connectivity_failure(self, mock_get_creds):
        """Test Lambda handler with VPN connectivity failure"""
        # Mock VPN connectivity validation failure
        self.mock_vpc_clients.validate_vpn_connectivity.side_effect = Exception('VPN tunnel down')
        
        result = lambda_handler(self.vpn_event, self.context)
        
        self.assertEqual(result['statusCode'], 503)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VPN_ERROR')
        self.assertIn('VPN connectivity validation failed', body['error']['message'])
    
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_vpn_enhanced')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials_vpc_with_retry')
    def test_lambda_handler_authentication_failure(self, mock_get_creds, mock_forward):
        """Test Lambda handler with authentication failure"""
        # Mock authentication failure
        mock_get_creds.side_effect = Exception('Invalid credentials')
        
        result = lambda_handler(self.vpn_event, self.context)
        
        self.assertEqual(result['statusCode'], 401)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'AUTHENTICATION_FAILED')
        self.assertIn('Failed to retrieve commercial credentials', body['error']['message'])
    
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_vpn_enhanced')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials_vpc_with_retry')
    def test_lambda_handler_service_error(self, mock_get_creds, mock_forward):
        """Test Lambda handler with service error"""
        # Mock successful credentials but Bedrock failure
        mock_get_creds.return_value = {'bedrock_api_key': 'test-key'}
        mock_forward.side_effect = Exception('Bedrock service unavailable')
        
        result = lambda_handler(self.vpn_event, self.context)
        
        self.assertEqual(result['statusCode'], 502)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'SERVICE_ERROR')
        self.assertIn('Failed to forward request to commercial Bedrock', body['error']['message'])
    
    def test_lambda_handler_missing_request_body(self):
        """Test Lambda handler with missing request body"""
        invalid_event = self.vpn_event.copy()
        del invalid_event['body']
        
        result = lambda_handler(invalid_event, self.context)
        
        self.assertEqual(result['statusCode'], 400)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VALIDATION_ERROR')
        self.assertIn('Missing request body', body['error']['message'])
    
    def test_lambda_handler_error_response_structure(self):
        """Test that error responses have proper structure"""
        # Test with invalid routing path
        internet_event = self.vpn_event.copy()
        internet_event['path'] = '/v1/bedrock/invoke-model'
        
        result = lambda_handler(internet_event, self.context)
        
        # Verify error response structure
        self.assertEqual(result['statusCode'], 400)
        self.assertIn('Content-Type', result['headers'])
        self.assertIn('X-Request-ID', result['headers'])
        self.assertIn('X-Routing-Method', result['headers'])
        
        body = json.loads(result['body'])
        self.assertIn('error', body)
        
        error = body['error']
        required_fields = ['code', 'message', 'category', 'routing_method', 'request_id', 'timestamp']
        for field in required_fields:
            self.assertIn(field, error, f"Missing required error field: {field}")
        
        # Check for troubleshooting information
        self.assertIn('troubleshooting', error)
        self.assertIn('description', error['troubleshooting'])

class TestVPNLambdaIntegration(unittest.TestCase):
    """Integration tests for VPN Lambda function components"""
    
    def setUp(self):
        """Set up integration test fixtures"""
        self.env_patcher = patch.dict(os.environ, {
            'VPC_ENDPOINT_SECRETS': 'https://vpce-secrets.us-gov-west-1.vpce.amazonaws.com',
            'ROUTING_METHOD': 'vpn'
        })
        self.env_patcher.start()
    
    def tearDown(self):
        """Clean up integration test fixtures"""
        self.env_patcher.stop()
    
    def test_error_handler_integration(self):
        """Test integration with error handler"""
        from dual_routing_error_handler import ErrorHandler
        
        error_handler = ErrorHandler('vpn')
        
        # Test VPN-specific error
        vpn_error = VPNError('VPN tunnel down', 'vpn', {'tunnel_id': 'vpn-12345'})
        
        result = error_handler.handle_error(vpn_error, 'test-request-id')
        
        self.assertEqual(result['statusCode'], 503)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VPN_ERROR')
        self.assertEqual(body['error']['category'], 'vpn_specific')
        self.assertTrue(body['error']['retryable'])
    
    @patch('dual_routing_vpn_lambda.vpc_clients')
    def test_vpc_endpoint_clients_integration(self, mock_vpc_clients):
        """Test VPC endpoint clients integration"""
        # Mock health status
        mock_vpc_clients.get_health_status.return_value = {
            'secrets': {'healthy': True, 'last_check': '2023-01-01T00:00:00Z'},
            'dynamodb': {'healthy': False, 'error': 'Connection timeout'},
            'vpn_tunnel': {'healthy': True, 'endpoint': 'test-endpoint'}
        }
        
        # Test health status retrieval
        health_status = mock_vpc_clients.get_health_status()
        
        self.assertTrue(health_status['secrets']['healthy'])
        self.assertFalse(health_status['dynamodb']['healthy'])
        self.assertIn('error', health_status['dynamodb'])

if __name__ == '__main__':
    # Configure test runner
    unittest.main(verbosity=2, buffer=True)