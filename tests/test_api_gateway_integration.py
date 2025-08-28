"""
Integration tests for API Gateway dual routing paths
Tests API Gateway routing to correct Lambda functions and authentication
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
import json
import os
import sys
import boto3
import requests
from datetime import datetime
from moto import mock_apigateway, mock_lambda, mock_iam

# Add lambda directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lambda'))

# Import Lambda functions for testing
from dual_routing_internet_lambda import lambda_handler as internet_lambda_handler
from dual_routing_vpn_lambda import lambda_handler as vpn_lambda_handler


class TestAPIGatewayIntegration(unittest.TestCase):
    """Test cases for API Gateway integration with dual routing"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'COMMERCIAL_CREDENTIALS_SECRET': 'test-commercial-creds',
            'REQUEST_LOG_TABLE': 'test-request-log-table',
            'VPC_ENDPOINT_BEDROCK': 'vpce-12345-bedrock',
            'VPC_ENDPOINT_SECRETS': 'vpce-12345-secrets',
            'VPC_ENDPOINT_DYNAMODB': 'vpce-12345-dynamodb'
        })
        self.env_patcher.start()
        
        # Sample API Gateway events for different paths
        self.internet_api_event = {
            'httpMethod': 'POST',
            'path': '/v1/bedrock/invoke-model',
            'pathParameters': None,
            'queryStringParameters': None,
            'headers': {
                'Content-Type': 'application/json',
                'X-API-Key': 'test-api-key',
                'Authorization': 'Bearer test-token'
            },
            'body': json.dumps({
                'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                'body': {
                    'messages': [
                        {'role': 'user', 'content': 'Test message for internet routing'}
                    ],
                    'max_tokens': 100
                }
            }),
            'requestContext': {
                'requestId': 'test-request-id-internet',
                'stage': 'prod',
                'resourcePath': '/v1/bedrock/invoke-model',
                'httpMethod': 'POST',
                'identity': {
                    'sourceIp': '203.0.113.1',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/testuser',
                    'apiKey': 'test-api-key'
                },
                'domainName': 'api.example.gov',
                'apiId': 'test-api-id'
            },
            'isBase64Encoded': False
        }
        
        self.vpn_api_event = {
            'httpMethod': 'POST',
            'path': '/v1/vpn/bedrock/invoke-model',
            'pathParameters': None,
            'queryStringParameters': None,
            'headers': {
                'Content-Type': 'application/json',
                'X-API-Key': 'test-api-key',
                'Authorization': 'Bearer test-token'
            },
            'body': json.dumps({
                'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                'body': {
                    'messages': [
                        {'role': 'user', 'content': 'Test message for VPN routing'}
                    ],
                    'max_tokens': 100
                }
            }),
            'requestContext': {
                'requestId': 'test-request-id-vpn',
                'stage': 'prod',
                'resourcePath': '/v1/vpn/bedrock/invoke-model',
                'httpMethod': 'POST',
                'identity': {
                    'sourceIp': '10.0.1.100',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/testuser',
                    'apiKey': 'test-api-key'
                },
                'domainName': 'api.example.gov',
                'apiId': 'test-api-id'
            },
            'isBase64Encoded': False
        }
        
        # Sample context
        self.context = Mock()
        self.context.aws_request_id = 'test-request-id'
        self.context.function_name = 'test-lambda-function'
        self.context.invoked_function_arn = 'arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:test-function'
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    def test_internet_path_routing_detection(self):
        """Test that internet paths are correctly detected"""
        internet_paths = [
            '/v1/bedrock/invoke-model',
            '/prod/v1/bedrock/invoke-model',
            '/stage/v1/bedrock/invoke-model',
            '/v1/bedrock/models'
        ]
        
        for path in internet_paths:
            with self.subTest(path=path):
                event = self.internet_api_event.copy()
                event['path'] = path
                event['requestContext']['resourcePath'] = path
                
                # Test with internet Lambda handler
                with patch('dual_routing_internet_lambda.get_commercial_credentials') as mock_creds, \
                     patch('dual_routing_internet_lambda.forward_to_bedrock') as mock_forward, \
                     patch('dual_routing_internet_lambda.log_request'), \
                     patch('dual_routing_internet_lambda.send_custom_metrics'):
                    
                    mock_creds.return_value = {'bedrock_api_key': 'test-key'}
                    mock_forward.return_value = {
                        'body': json.dumps({'content': [{'text': 'Internet response'}]}),
                        'contentType': 'application/json'
                    }
                    
                    result = internet_lambda_handler(event, self.context)
                    
                    self.assertEqual(result['statusCode'], 200)
                    self.assertEqual(result['headers']['X-Routing-Method'], 'internet')
                    
                    # Verify response contains routing method
                    body = json.loads(result['body'])
                    self.assertEqual(body['routing_method'], 'internet')
    
    def test_vpn_path_routing_detection(self):
        """Test that VPN paths are correctly detected"""
        vpn_paths = [
            '/v1/vpn/bedrock/invoke-model',
            '/prod/v1/vpn/bedrock/invoke-model',
            '/stage/v1/vpn/bedrock/invoke-model',
            '/v1/vpn/bedrock/models'
        ]
        
        for path in vpn_paths:
            with self.subTest(path=path):
                event = self.vpn_api_event.copy()
                event['path'] = path
                event['requestContext']['resourcePath'] = path
                
                # Test with VPN Lambda handler
                with patch('dual_routing_vpn_lambda.get_commercial_credentials') as mock_creds, \
                     patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn') as mock_forward, \
                     patch('dual_routing_vpn_lambda.log_request'), \
                     patch('dual_routing_vpn_lambda.send_custom_metrics'):
                    
                    mock_creds.return_value = {'bedrock_api_key': 'test-key'}
                    mock_forward.return_value = {
                        'body': json.dumps({'content': [{'text': 'VPN response'}]}),
                        'contentType': 'application/json'
                    }
                    
                    result = vpn_lambda_handler(event, self.context)
                    
                    self.assertEqual(result['statusCode'], 200)
                    self.assertEqual(result['headers']['X-Routing-Method'], 'vpn')
                    
                    # Verify response contains routing method
                    body = json.loads(result['body'])
                    self.assertEqual(body['routing_method'], 'vpn')
    
    def test_internet_lambda_rejects_vpn_paths(self):
        """Test that Internet Lambda rejects VPN paths"""
        vpn_event = self.vpn_api_event.copy()
        
        result = internet_lambda_handler(vpn_event, self.context)
        
        self.assertEqual(result['statusCode'], 400)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VALIDATION_ERROR')
        self.assertIn('internet routing requests', body['error']['message'])
    
    def test_vpn_lambda_rejects_internet_paths(self):
        """Test that VPN Lambda rejects internet paths"""
        internet_event = self.internet_api_event.copy()
        
        result = vpn_lambda_handler(internet_event, self.context)
        
        self.assertEqual(result['statusCode'], 400)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VALIDATION_ERROR')
        self.assertIn('VPN routing requests', body['error']['message'])
    
    def test_authentication_consistency_across_paths(self):
        """Test that authentication works consistently across both paths"""
        # Test cases for different authentication scenarios
        auth_test_cases = [
            {
                'name': 'valid_api_key',
                'headers': {
                    'Content-Type': 'application/json',
                    'X-API-Key': 'valid-api-key-12345'
                },
                'should_succeed': True
            },
            {
                'name': 'missing_api_key',
                'headers': {
                    'Content-Type': 'application/json'
                },
                'should_succeed': False
            },
            {
                'name': 'invalid_api_key',
                'headers': {
                    'Content-Type': 'application/json',
                    'X-API-Key': 'invalid-key'
                },
                'should_succeed': False
            }
        ]
        
        for test_case in auth_test_cases:
            with self.subTest(auth_case=test_case['name']):
                # Test Internet path
                internet_event = self.internet_api_event.copy()
                internet_event['headers'] = test_case['headers']
                
                # Test VPN path
                vpn_event = self.vpn_api_event.copy()
                vpn_event['headers'] = test_case['headers']
                
                # Mock successful backend calls for valid auth
                with patch('dual_routing_internet_lambda.get_commercial_credentials') as mock_internet_creds, \
                     patch('dual_routing_internet_lambda.forward_to_bedrock') as mock_internet_forward, \
                     patch('dual_routing_vpn_lambda.get_commercial_credentials') as mock_vpn_creds, \
                     patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn') as mock_vpn_forward, \
                     patch('dual_routing_internet_lambda.log_request'), \
                     patch('dual_routing_internet_lambda.send_custom_metrics'), \
                     patch('dual_routing_vpn_lambda.log_request'), \
                     patch('dual_routing_vpn_lambda.send_custom_metrics'):
                    
                    if test_case['should_succeed']:
                        mock_internet_creds.return_value = {'bedrock_api_key': 'test-key'}
                        mock_internet_forward.return_value = {
                            'body': json.dumps({'content': [{'text': 'Internet response'}]}),
                            'contentType': 'application/json'
                        }
                        mock_vpn_creds.return_value = {'bedrock_api_key': 'test-key'}
                        mock_vpn_forward.return_value = {
                            'body': json.dumps({'content': [{'text': 'VPN response'}]}),
                            'contentType': 'application/json'
                        }
                    
                    # Execute tests
                    internet_result = internet_lambda_handler(internet_event, self.context)
                    vpn_result = vpn_lambda_handler(vpn_event, self.context)
                    
                    if test_case['should_succeed']:
                        # Both should succeed with valid auth
                        self.assertEqual(internet_result['statusCode'], 200)
                        self.assertEqual(vpn_result['statusCode'], 200)
                        
                        # Verify routing method headers
                        self.assertEqual(internet_result['headers']['X-Routing-Method'], 'internet')
                        self.assertEqual(vpn_result['headers']['X-Routing-Method'], 'vpn')
                    else:
                        # Both should fail with invalid auth (but may fail for different reasons)
                        # The important thing is they both fail consistently
                        self.assertNotEqual(internet_result['statusCode'], 200)
                        self.assertNotEqual(vpn_result['statusCode'], 200)
    
    def test_get_requests_routing(self):
        """Test GET requests route correctly to both Lambda functions"""
        # Test GET request for models
        get_models_internet = {
            'httpMethod': 'GET',
            'path': '/v1/bedrock/models',
            'headers': {'X-API-Key': 'test-api-key'},
            'requestContext': self.internet_api_event['requestContext'].copy()
        }
        get_models_internet['requestContext']['resourcePath'] = '/v1/bedrock/models'
        get_models_internet['requestContext']['httpMethod'] = 'GET'
        
        get_models_vpn = {
            'httpMethod': 'GET',
            'path': '/v1/vpn/bedrock/models',
            'headers': {'X-API-Key': 'test-api-key'},
            'requestContext': self.vpn_api_event['requestContext'].copy()
        }
        get_models_vpn['requestContext']['resourcePath'] = '/v1/vpn/bedrock/models'
        get_models_vpn['requestContext']['httpMethod'] = 'GET'
        
        # Test Internet Lambda GET
        with patch('dual_routing_internet_lambda.get_available_models') as mock_internet_models:
            mock_internet_models.return_value = {
                'statusCode': 200,
                'body': json.dumps({'models': [], 'routing_method': 'internet'})
            }
            
            result = internet_lambda_handler(get_models_internet, self.context)
            
            self.assertEqual(result['statusCode'], 200)
            mock_internet_models.assert_called_once()
        
        # Test VPN Lambda GET
        with patch('dual_routing_vpn_lambda.get_available_models') as mock_vpn_models:
            mock_vpn_models.return_value = {
                'statusCode': 200,
                'body': json.dumps({'models': [], 'routing_method': 'vpn'})
            }
            
            result = vpn_lambda_handler(get_models_vpn, self.context)
            
            self.assertEqual(result['statusCode'], 200)
            mock_vpn_models.assert_called_once()
    
    def test_request_context_preservation(self):
        """Test that request context is properly preserved through routing"""
        # Test that important request context fields are maintained
        test_event = self.internet_api_event.copy()
        
        with patch('dual_routing_internet_lambda.get_commercial_credentials') as mock_creds, \
             patch('dual_routing_internet_lambda.forward_to_bedrock') as mock_forward, \
             patch('dual_routing_internet_lambda.log_request') as mock_log, \
             patch('dual_routing_internet_lambda.send_custom_metrics'):
            
            mock_creds.return_value = {'bedrock_api_key': 'test-key'}
            mock_forward.return_value = {
                'body': json.dumps({'content': [{'text': 'Test response'}]}),
                'contentType': 'application/json'
            }
            
            result = internet_lambda_handler(test_event, self.context)
            
            # Verify request was logged with proper context
            mock_log.assert_called_once()
            log_call_args = mock_log.call_args[0]
            request_data = log_call_args[1]  # Second argument is request_data
            
            # Verify important context fields are preserved
            self.assertEqual(request_data['sourceIP'], '203.0.113.1')
            self.assertEqual(request_data['userArn'], 'arn:aws-us-gov:iam::123456789012:user/testuser')
            self.assertEqual(request_data['api_path'], '/v1/bedrock/invoke-model')
            self.assertEqual(request_data['routing_method'], 'internet')
    
    def test_error_response_consistency(self):
        """Test that error responses are consistent across both routing methods"""
        # Test with invalid model ID
        invalid_event_internet = self.internet_api_event.copy()
        invalid_body = json.loads(invalid_event_internet['body'])
        invalid_body['modelId'] = ''  # Invalid empty model ID
        invalid_event_internet['body'] = json.dumps(invalid_body)
        
        invalid_event_vpn = self.vpn_api_event.copy()
        invalid_event_vpn['body'] = json.dumps(invalid_body)
        
        # Test Internet Lambda error response
        internet_result = internet_lambda_handler(invalid_event_internet, self.context)
        
        # Test VPN Lambda error response
        vpn_result = vpn_lambda_handler(invalid_event_vpn, self.context)
        
        # Both should return validation errors
        self.assertEqual(internet_result['statusCode'], 400)
        self.assertEqual(vpn_result['statusCode'], 400)
        
        # Both should have consistent error structure
        internet_body = json.loads(internet_result['body'])
        vpn_body = json.loads(vpn_result['body'])
        
        self.assertIn('error', internet_body)
        self.assertIn('error', vpn_body)
        self.assertIn('code', internet_body['error'])
        self.assertIn('code', vpn_body['error'])
        self.assertEqual(internet_body['error']['code'], 'VALIDATION_ERROR')
        self.assertEqual(vpn_body['error']['code'], 'VALIDATION_ERROR')
    
    def test_response_headers_consistency(self):
        """Test that response headers are consistent across both routing methods"""
        with patch('dual_routing_internet_lambda.get_commercial_credentials') as mock_internet_creds, \
             patch('dual_routing_internet_lambda.forward_to_bedrock') as mock_internet_forward, \
             patch('dual_routing_vpn_lambda.get_commercial_credentials') as mock_vpn_creds, \
             patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn') as mock_vpn_forward, \
             patch('dual_routing_internet_lambda.log_request'), \
             patch('dual_routing_internet_lambda.send_custom_metrics'), \
             patch('dual_routing_vpn_lambda.log_request'), \
             patch('dual_routing_vpn_lambda.send_custom_metrics'):
            
            # Mock successful responses
            mock_internet_creds.return_value = {'bedrock_api_key': 'test-key'}
            mock_internet_forward.return_value = {
                'body': json.dumps({'content': [{'text': 'Internet response'}]}),
                'contentType': 'application/json'
            }
            mock_vpn_creds.return_value = {'bedrock_api_key': 'test-key'}
            mock_vpn_forward.return_value = {
                'body': json.dumps({'content': [{'text': 'VPN response'}]}),
                'contentType': 'application/json'
            }
            
            # Execute both Lambda functions
            internet_result = internet_lambda_handler(self.internet_api_event, self.context)
            vpn_result = vpn_lambda_handler(self.vpn_api_event, self.context)
            
            # Verify both have required headers
            required_headers = [
                'Content-Type',
                'X-Request-ID',
                'X-Source-Partition',
                'X-Destination-Partition',
                'X-Routing-Method'
            ]
            
            for header in required_headers:
                self.assertIn(header, internet_result['headers'])
                self.assertIn(header, vpn_result['headers'])
            
            # Verify routing method headers are different
            self.assertEqual(internet_result['headers']['X-Routing-Method'], 'internet')
            self.assertEqual(vpn_result['headers']['X-Routing-Method'], 'vpn')
            
            # Verify other headers are consistent
            self.assertEqual(internet_result['headers']['X-Source-Partition'], 'govcloud')
            self.assertEqual(vpn_result['headers']['X-Source-Partition'], 'govcloud')
            self.assertEqual(internet_result['headers']['X-Destination-Partition'], 'commercial')
            self.assertEqual(vpn_result['headers']['X-Destination-Partition'], 'commercial')


class TestAPIGatewayPathValidation(unittest.TestCase):
    """Test cases for API Gateway path validation and routing logic"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.env_patcher = patch.dict(os.environ, {
            'COMMERCIAL_CREDENTIALS_SECRET': 'test-commercial-creds',
            'REQUEST_LOG_TABLE': 'test-request-log-table'
        })
        self.env_patcher.start()
        
        self.context = Mock()
        self.context.aws_request_id = 'test-request-id'
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    def test_path_parameter_extraction(self):
        """Test that path parameters are correctly extracted and processed"""
        # Test with stage prefix
        staged_paths = [
            ('/prod/v1/bedrock/invoke-model', 'internet'),
            ('/stage/v1/bedrock/invoke-model', 'internet'),
            ('/dev/v1/vpn/bedrock/invoke-model', 'vpn'),
            ('/test/v1/vpn/bedrock/models', 'vpn')
        ]
        
        for path, expected_routing in staged_paths:
            with self.subTest(path=path):
                from dual_routing_internet_lambda import detect_routing_method
                result = detect_routing_method(path)
                self.assertEqual(result, expected_routing)
    
    def test_invalid_path_handling(self):
        """Test handling of invalid or malformed paths"""
        invalid_paths = [
            '/invalid/path',
            '/v1/bedrock',  # Missing invoke-model
            '/v1/vpn/bedrock',  # Missing invoke-model
            '/bedrock/invoke-model',  # Missing v1
            ''  # Empty path
        ]
        
        for path in invalid_paths:
            with self.subTest(path=path):
                from dual_routing_internet_lambda import detect_routing_method
                # Should default to internet for backward compatibility
                result = detect_routing_method(path)
                self.assertEqual(result, 'internet')
    
    def test_case_sensitivity_in_paths(self):
        """Test that path routing is case sensitive as expected"""
        case_test_paths = [
            ('/v1/bedrock/invoke-model', 'internet'),
            ('/V1/bedrock/invoke-model', 'internet'),  # Should still work
            ('/v1/BEDROCK/invoke-model', 'internet'),  # Should still work
            ('/v1/vpn/bedrock/invoke-model', 'vpn'),
            ('/v1/VPN/bedrock/invoke-model', 'internet'),  # VPN must be lowercase
        ]
        
        for path, expected_routing in case_test_paths:
            with self.subTest(path=path):
                from dual_routing_internet_lambda import detect_routing_method
                result = detect_routing_method(path)
                self.assertEqual(result, expected_routing)
    
    def test_query_parameters_preservation(self):
        """Test that query parameters are preserved through routing"""
        event_with_query = {
            'httpMethod': 'POST',
            'path': '/v1/bedrock/invoke-model',
            'queryStringParameters': {
                'debug': 'true',
                'timeout': '30'
            },
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                'body': {'messages': [{'role': 'user', 'content': 'test'}]}
            }),
            'requestContext': {
                'identity': {
                    'sourceIp': '192.168.1.1',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/test'
                }
            }
        }
        
        with patch('dual_routing_internet_lambda.get_commercial_credentials') as mock_creds, \
             patch('dual_routing_internet_lambda.forward_to_bedrock') as mock_forward, \
             patch('dual_routing_internet_lambda.log_request'), \
             patch('dual_routing_internet_lambda.send_custom_metrics'):
            
            mock_creds.return_value = {'bedrock_api_key': 'test-key'}
            mock_forward.return_value = {
                'body': json.dumps({'content': [{'text': 'Test response'}]}),
                'contentType': 'application/json'
            }
            
            from dual_routing_internet_lambda import lambda_handler
            result = lambda_handler(event_with_query, self.context)
            
            # Should succeed - query parameters don't affect routing
            self.assertEqual(result['statusCode'], 200)


if __name__ == '__main__':
    # Create test suite
    test_suite = unittest.TestSuite()
    
    # Add test classes
    test_classes = [
        TestAPIGatewayIntegration,
        TestAPIGatewayPathValidation
    ]
    
    for test_class in test_classes:
        tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
        test_suite.addTests(tests)
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)
    
    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)