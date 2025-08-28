"""
End-to-end tests for dual routing system
Tests complete flow from API Gateway through Lambda functions to Bedrock
"""

import unittest
from unittest.mock import Mock, patch, MagicMock, call
import json
import os
import sys
import time
import uuid
from datetime import datetime
import boto3
from botocore.exceptions import ClientError

# Add lambda directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lambda'))

# Import Lambda functions for testing
from dual_routing_internet_lambda import lambda_handler as internet_lambda_handler
from dual_routing_vpn_lambda import lambda_handler as vpn_lambda_handler


class TestEndToEndInternetRouting(unittest.TestCase):
    """End-to-end tests for internet routing flow"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'COMMERCIAL_CREDENTIALS_SECRET': 'test-commercial-creds',
            'REQUEST_LOG_TABLE': 'test-request-log-table',
            'AWS_REGION': 'us-gov-west-1'
        })
        self.env_patcher.start()
        
        # Sample end-to-end API Gateway event for internet routing
        self.e2e_internet_event = {
            'httpMethod': 'POST',
            'path': '/v1/bedrock/invoke-model',
            'pathParameters': None,
            'queryStringParameters': None,
            'headers': {
                'Content-Type': 'application/json',
                'X-API-Key': 'test-api-key-12345',
                'Authorization': 'Bearer test-token',
                'User-Agent': 'DualRoutingClient/1.0',
                'X-Forwarded-For': '203.0.113.1'
            },
            'body': json.dumps({
                'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                'contentType': 'application/json',
                'accept': 'application/json',
                'body': {
                    'messages': [
                        {
                            'role': 'user',
                            'content': 'This is an end-to-end test message for internet routing. Please respond with a confirmation.'
                        }
                    ],
                    'max_tokens': 150,
                    'temperature': 0.7
                }
            }),
            'requestContext': {
                'requestId': f'e2e-test-{uuid.uuid4()}',
                'stage': 'prod',
                'resourcePath': '/v1/bedrock/invoke-model',
                'httpMethod': 'POST',
                'identity': {
                    'sourceIp': '203.0.113.1',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/e2e-test-user',
                    'apiKey': 'test-api-key-12345',
                    'userAgent': 'DualRoutingClient/1.0'
                },
                'domainName': 'api.example.gov',
                'apiId': 'test-api-gateway-id',
                'requestTime': datetime.utcnow().strftime('%d/%b/%Y:%H:%M:%S +0000'),
                'requestTimeEpoch': int(time.time())
            },
            'isBase64Encoded': False
        }
        
        # Sample context
        self.context = Mock()
        self.context.aws_request_id = f'e2e-test-{uuid.uuid4()}'
        self.context.function_name = 'dual-routing-internet-lambda'
        self.context.invoked_function_arn = 'arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:dual-routing-internet-lambda'
        self.context.memory_limit_in_mb = '512'
        self.context.remaining_time_in_millis = lambda: 30000
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    @patch('dual_routing_internet_lambda.boto3.client')
    @patch('dual_routing_internet_lambda.dynamodb')
    @patch('dual_routing_internet_lambda.secrets_client')
    @patch('dual_routing_internet_lambda.urllib.request.urlopen')
    def test_complete_internet_routing_flow_with_api_key(self, mock_urlopen, mock_secrets_client, 
                                                        mock_dynamodb, mock_boto3_client):
        """Test complete end-to-end internet routing flow using API key"""
        # Mock Secrets Manager response
        mock_secrets_response = {
            'SecretString': json.dumps({
                'bedrock_api_key': 'dGVzdC1hcGkta2V5LTEyMzQ1',  # base64 encoded test key
                'region': 'us-east-1'
            })
        }
        mock_secrets_client.get_secret_value.return_value = mock_secrets_response
        
        # Mock successful Bedrock API response via internet
        mock_bedrock_response = {
            'content': [
                {
                    'text': 'This is a test response from commercial Bedrock via internet routing. The end-to-end test is working correctly.'
                }
            ],
            'usage': {
                'input_tokens': 25,
                'output_tokens': 20
            }
        }
        
        mock_http_response = Mock()
        mock_http_response.read.return_value = json.dumps(mock_bedrock_response).encode('utf-8')
        mock_http_response.headers = {'content-type': 'application/json'}
        mock_urlopen.return_value.__enter__.return_value = mock_http_response
        
        # Mock DynamoDB table for request logging
        mock_table = Mock()
        mock_dynamodb.Table.return_value = mock_table
        
        # Mock CloudWatch client for metrics
        mock_cloudwatch = Mock()
        mock_boto3_client.return_value = mock_cloudwatch
        
        # Execute end-to-end test
        start_time = time.time()
        result = internet_lambda_handler(self.e2e_internet_event, self.context)
        end_time = time.time()
        
        # Verify successful response
        self.assertEqual(result['statusCode'], 200)
        
        # Verify response headers
        self.assertIn('X-Routing-Method', result['headers'])
        self.assertEqual(result['headers']['X-Routing-Method'], 'internet')
        self.assertIn('X-Request-ID', result['headers'])
        self.assertEqual(result['headers']['X-Source-Partition'], 'govcloud')
        self.assertEqual(result['headers']['X-Destination-Partition'], 'commercial')
        
        # Verify response body
        response_body = json.loads(result['body'])
        self.assertEqual(response_body['routing_method'], 'internet')
        self.assertIn('content', response_body)
        self.assertIn('usage', response_body)
        
        # Verify Bedrock API was called correctly
        mock_urlopen.assert_called_once()
        call_args = mock_urlopen.call_args[0][0]  # Get the Request object
        self.assertIn('bedrock-runtime.us-east-1.amazonaws.com', call_args.full_url)
        self.assertIn('anthropic.claude-3-haiku-20240307-v1:0', call_args.full_url)
        
        # Verify request was logged to DynamoDB
        mock_table.put_item.assert_called_once()
        log_entry = mock_table.put_item.call_args[1]['Item']
        self.assertEqual(log_entry['routingMethod'], 'internet')
        self.assertTrue(log_entry['success'])
        self.assertIn('latency', log_entry)
        
        # Verify metrics were sent to CloudWatch
        mock_cloudwatch.put_metric_data.assert_called_once()
        metrics_call = mock_cloudwatch.put_metric_data.call_args[1]
        self.assertEqual(metrics_call['Namespace'], 'CrossPartition/DualRouting')
        
        # Verify end-to-end latency is reasonable
        e2e_latency = (end_time - start_time) * 1000  # Convert to milliseconds
        self.assertLess(e2e_latency, 5000, "End-to-end latency should be under 5 seconds")
    
    @patch('dual_routing_internet_lambda.create_bedrock_session')
    @patch('dual_routing_internet_lambda.dynamodb')
    @patch('dual_routing_internet_lambda.secrets_client')
    @patch('dual_routing_internet_lambda.boto3.client')
    def test_complete_internet_routing_flow_with_aws_credentials(self, mock_boto3_client, 
                                                               mock_secrets_client, mock_dynamodb, 
                                                               mock_create_session):
        """Test complete end-to-end internet routing flow using AWS credentials"""
        # Mock Secrets Manager response with AWS credentials
        mock_secrets_response = {
            'SecretString': json.dumps({
                'aws_access_key_id': 'AKIA12345EXAMPLE',
                'aws_secret_access_key': 'secret12345example',
                'region': 'us-east-1'
            })
        }
        mock_secrets_client.get_secret_value.return_value = mock_secrets_response
        
        # Mock AWS session and Bedrock client
        mock_session = Mock()
        mock_bedrock_client = Mock()
        mock_create_session.return_value = mock_session
        mock_session.client.return_value = mock_bedrock_client
        
        # Mock successful Bedrock response
        mock_bedrock_response = {
            'content': [
                {
                    'text': 'This is a test response from commercial Bedrock via internet routing using AWS credentials.'
                }
            ],
            'usage': {
                'input_tokens': 30,
                'output_tokens': 18
            }
        }
        
        mock_response_body = Mock()
        mock_response_body.read.return_value = json.dumps(mock_bedrock_response).encode('utf-8')
        mock_bedrock_client.invoke_model.return_value = {
            'body': mock_response_body,
            'contentType': 'application/json'
        }
        
        # Mock DynamoDB and CloudWatch
        mock_table = Mock()
        mock_dynamodb.Table.return_value = mock_table
        mock_cloudwatch = Mock()
        mock_boto3_client.return_value = mock_cloudwatch
        
        # Execute end-to-end test
        result = internet_lambda_handler(self.e2e_internet_event, self.context)
        
        # Verify successful response
        self.assertEqual(result['statusCode'], 200)
        
        # Verify AWS credentials were used
        mock_create_session.assert_called_once()
        mock_bedrock_client.invoke_model.assert_called_once()
        
        # Verify response contains AWS credentials metadata
        response_body = json.loads(result['body'])
        self.assertTrue(response_body.get('aws_credentials_used', False))
    
    @patch('dual_routing_internet_lambda.secrets_client')
    def test_end_to_end_internet_routing_authentication_failure(self, mock_secrets_client):
        """Test end-to-end internet routing with authentication failure"""
        # Mock authentication failure
        mock_secrets_client.get_secret_value.side_effect = ClientError(
            {'Error': {'Code': 'ResourceNotFoundException', 'Message': 'Secret not found'}},
            'GetSecretValue'
        )
        
        # Execute test
        result = internet_lambda_handler(self.e2e_internet_event, self.context)
        
        # Verify authentication error response
        self.assertEqual(result['statusCode'], 401)
        response_body = json.loads(result['body'])
        self.assertEqual(response_body['error']['code'], 'AUTHENTICATION_FAILED')
        self.assertIn('Failed to retrieve commercial credentials', response_body['error']['message'])
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    @patch('dual_routing_internet_lambda.urllib.request.urlopen')
    def test_end_to_end_internet_routing_network_failure(self, mock_urlopen, mock_get_creds):
        """Test end-to-end internet routing with network failure"""
        # Mock successful credentials
        mock_get_creds.return_value = {'bedrock_api_key': 'test-key'}
        
        # Mock network failure
        mock_urlopen.side_effect = Exception('Connection timeout')
        
        # Execute test
        result = internet_lambda_handler(self.e2e_internet_event, self.context)
        
        # Verify network error response
        self.assertEqual(result['statusCode'], 502)
        response_body = json.loads(result['body'])
        self.assertEqual(response_body['error']['code'], 'NETWORK_ERROR')
        self.assertIn('Network error occurred', response_body['error']['message'])


class TestEndToEndVPNRouting(unittest.TestCase):
    """End-to-end tests for VPN routing flow"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'COMMERCIAL_CREDENTIALS_SECRET': 'test-commercial-creds',
            'REQUEST_LOG_TABLE': 'test-request-log-table',
            'VPC_ENDPOINT_BEDROCK': 'vpce-12345-bedrock',
            'VPC_ENDPOINT_SECRETS': 'vpce-12345-secrets',
            'VPC_ENDPOINT_DYNAMODB': 'vpce-12345-dynamodb',
            'AWS_REGION': 'us-gov-west-1'
        })
        self.env_patcher.start()
        
        # Sample end-to-end API Gateway event for VPN routing
        self.e2e_vpn_event = {
            'httpMethod': 'POST',
            'path': '/v1/vpn/bedrock/invoke-model',
            'pathParameters': None,
            'queryStringParameters': None,
            'headers': {
                'Content-Type': 'application/json',
                'X-API-Key': 'test-vpn-api-key-12345',
                'Authorization': 'Bearer test-vpn-token',
                'User-Agent': 'DualRoutingVPNClient/1.0',
                'X-Forwarded-For': '10.0.1.100'
            },
            'body': json.dumps({
                'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                'contentType': 'application/json',
                'accept': 'application/json',
                'body': {
                    'messages': [
                        {
                            'role': 'user',
                            'content': 'This is an end-to-end test message for VPN routing. Please respond with a confirmation.'
                        }
                    ],
                    'max_tokens': 150,
                    'temperature': 0.7
                }
            }),
            'requestContext': {
                'requestId': f'e2e-vpn-test-{uuid.uuid4()}',
                'stage': 'prod',
                'resourcePath': '/v1/vpn/bedrock/invoke-model',
                'httpMethod': 'POST',
                'identity': {
                    'sourceIp': '10.0.1.100',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/e2e-vpn-test-user',
                    'apiKey': 'test-vpn-api-key-12345',
                    'userAgent': 'DualRoutingVPNClient/1.0'
                },
                'domainName': 'api.example.gov',
                'apiId': 'test-api-gateway-id',
                'requestTime': datetime.utcnow().strftime('%d/%b/%Y:%H:%M:%S +0000'),
                'requestTimeEpoch': int(time.time())
            },
            'isBase64Encoded': False
        }
        
        # Sample context
        self.context = Mock()
        self.context.aws_request_id = f'e2e-vpn-test-{uuid.uuid4()}'
        self.context.function_name = 'dual-routing-vpn-lambda'
        self.context.invoked_function_arn = 'arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:dual-routing-vpn-lambda'
        self.context.memory_limit_in_mb = '512'
        self.context.remaining_time_in_millis = lambda: 30000
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    @patch('dual_routing_vpn_lambda.boto3.client')
    @patch('dual_routing_vpn_lambda.dynamodb')
    @patch('dual_routing_vpn_lambda.secrets_client')
    @patch('dual_routing_vpn_lambda.create_vpc_bedrock_client')
    def test_complete_vpn_routing_flow(self, mock_create_vpc_client, mock_secrets_client, 
                                      mock_dynamodb, mock_boto3_client):
        """Test complete end-to-end VPN routing flow"""
        # Mock Secrets Manager response
        mock_secrets_response = {
            'SecretString': json.dumps({
                'aws_access_key_id': 'AKIA12345VPNTEST',
                'aws_secret_access_key': 'secret12345vpntest',
                'region': 'us-east-1'
            })
        }
        mock_secrets_client.get_secret_value.return_value = mock_secrets_response
        
        # Mock VPC Bedrock client
        mock_vpc_bedrock_client = Mock()
        mock_create_vpc_client.return_value = mock_vpc_bedrock_client
        
        # Mock successful Bedrock response via VPN
        mock_bedrock_response = {
            'content': [
                {
                    'text': 'This is a test response from commercial Bedrock via VPN routing. The end-to-end VPN test is working correctly.'
                }
            ],
            'usage': {
                'input_tokens': 28,
                'output_tokens': 22
            }
        }
        
        mock_response_body = Mock()
        mock_response_body.read.return_value = json.dumps(mock_bedrock_response).encode('utf-8')
        mock_vpc_bedrock_client.invoke_model.return_value = {
            'body': mock_response_body,
            'contentType': 'application/json'
        }
        
        # Mock DynamoDB table for request logging
        mock_table = Mock()
        mock_dynamodb.Table.return_value = mock_table
        
        # Mock CloudWatch client for metrics
        mock_cloudwatch = Mock()
        mock_boto3_client.return_value = mock_cloudwatch
        
        # Execute end-to-end VPN test
        start_time = time.time()
        result = vpn_lambda_handler(self.e2e_vpn_event, self.context)
        end_time = time.time()
        
        # Verify successful response
        self.assertEqual(result['statusCode'], 200)
        
        # Verify response headers
        self.assertIn('X-Routing-Method', result['headers'])
        self.assertEqual(result['headers']['X-Routing-Method'], 'vpn')
        self.assertIn('X-Request-ID', result['headers'])
        self.assertEqual(result['headers']['X-Source-Partition'], 'govcloud')
        self.assertEqual(result['headers']['X-Destination-Partition'], 'commercial')
        
        # Verify response body
        response_body = json.loads(result['body'])
        self.assertEqual(response_body['routing_method'], 'vpn')
        self.assertIn('content', response_body)
        self.assertIn('usage', response_body)
        
        # Verify VPC Bedrock client was created and used
        mock_create_vpc_client.assert_called_once()
        mock_vpc_bedrock_client.invoke_model.assert_called_once()
        
        # Verify request was logged to DynamoDB
        mock_table.put_item.assert_called_once()
        log_entry = mock_table.put_item.call_args[1]['Item']
        self.assertEqual(log_entry['routingMethod'], 'vpn')
        self.assertTrue(log_entry['success'])
        self.assertIn('latency', log_entry)
        
        # Verify metrics were sent to CloudWatch
        mock_cloudwatch.put_metric_data.assert_called_once()
        metrics_call = mock_cloudwatch.put_metric_data.call_args[1]
        self.assertEqual(metrics_call['Namespace'], 'CrossPartition/DualRouting')
        
        # Verify end-to-end latency is reasonable
        e2e_latency = (end_time - start_time) * 1000  # Convert to milliseconds
        self.assertLess(e2e_latency, 5000, "End-to-end VPN latency should be under 5 seconds")
    
    @patch('dual_routing_vpn_lambda.create_vpc_bedrock_client')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials')
    def test_end_to_end_vpn_routing_vpc_endpoint_failure(self, mock_get_creds, mock_create_vpc_client):
        """Test end-to-end VPN routing with VPC endpoint failure"""
        # Mock successful credentials
        mock_get_creds.return_value = {
            'aws_access_key_id': 'AKIA12345',
            'aws_secret_access_key': 'secret12345',
            'region': 'us-east-1'
        }
        
        # Mock VPC endpoint failure
        mock_create_vpc_client.side_effect = Exception('VPC endpoint connection failed')
        
        # Execute test
        result = vpn_lambda_handler(self.e2e_vpn_event, self.context)
        
        # Verify VPC endpoint error response
        self.assertEqual(result['statusCode'], 502)
        response_body = json.loads(result['body'])
        self.assertEqual(response_body['error']['code'], 'NETWORK_ERROR')
        self.assertIn('VPC endpoint connection failed', response_body['error']['message'])


class TestEndToEndRoutingComparison(unittest.TestCase):
    """Tests comparing functional equivalence between routing methods"""
    
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
        
        # Common request payload for comparison
        self.common_request_body = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'contentType': 'application/json',
            'accept': 'application/json',
            'body': {
                'messages': [
                    {
                        'role': 'user',
                        'content': 'This is a comparison test message. Please respond consistently.'
                    }
                ],
                'max_tokens': 100,
                'temperature': 0.5
            }
        }
        
        # Internet routing event
        self.internet_event = {
            'httpMethod': 'POST',
            'path': '/v1/bedrock/invoke-model',
            'headers': {'Content-Type': 'application/json', 'X-API-Key': 'test-key'},
            'body': json.dumps(self.common_request_body),
            'requestContext': {
                'identity': {
                    'sourceIp': '203.0.113.1',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/test'
                }
            }
        }
        
        # VPN routing event
        self.vpn_event = {
            'httpMethod': 'POST',
            'path': '/v1/vpn/bedrock/invoke-model',
            'headers': {'Content-Type': 'application/json', 'X-API-Key': 'test-key'},
            'body': json.dumps(self.common_request_body),
            'requestContext': {
                'identity': {
                    'sourceIp': '10.0.1.100',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/test'
                }
            }
        }
        
        self.context = Mock()
        self.context.aws_request_id = 'comparison-test-id'
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_internet_lambda.log_request')
    @patch('dual_routing_internet_lambda.send_custom_metrics')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials')
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn')
    @patch('dual_routing_vpn_lambda.log_request')
    @patch('dual_routing_vpn_lambda.send_custom_metrics')
    def test_functional_equivalence_between_routing_methods(self, 
                                                           mock_vpn_metrics, mock_vpn_log, mock_vpn_forward, mock_vpn_creds,
                                                           mock_internet_metrics, mock_internet_log, mock_internet_forward, mock_internet_creds):
        """Test that both routing methods produce functionally equivalent results"""
        # Mock identical credentials for both methods
        mock_credentials = {'bedrock_api_key': 'test-key'}
        mock_internet_creds.return_value = mock_credentials
        mock_vpn_creds.return_value = mock_credentials
        
        # Mock identical Bedrock responses for both methods
        mock_bedrock_response = {
            'body': json.dumps({
                'content': [{'text': 'Consistent test response from Bedrock'}],
                'usage': {'input_tokens': 15, 'output_tokens': 8}
            }),
            'contentType': 'application/json'
        }
        mock_internet_forward.return_value = mock_bedrock_response
        mock_vpn_forward.return_value = mock_bedrock_response
        
        # Execute both routing methods
        internet_result = internet_lambda_handler(self.internet_event, self.context)
        vpn_result = vpn_lambda_handler(self.vpn_event, self.context)
        
        # Verify both succeed
        self.assertEqual(internet_result['statusCode'], 200)
        self.assertEqual(vpn_result['statusCode'], 200)
        
        # Parse response bodies
        internet_body = json.loads(internet_result['body'])
        vpn_body = json.loads(vpn_result['body'])
        
        # Verify functional equivalence (same content, different routing metadata)
        self.assertEqual(internet_body['content'], vpn_body['content'])
        self.assertEqual(internet_body['usage'], vpn_body['usage'])
        
        # Verify routing method differences
        self.assertEqual(internet_body['routing_method'], 'internet')
        self.assertEqual(vpn_body['routing_method'], 'vpn')
        self.assertEqual(internet_result['headers']['X-Routing-Method'], 'internet')
        self.assertEqual(vpn_result['headers']['X-Routing-Method'], 'vpn')
        
        # Verify both methods logged requests
        mock_internet_log.assert_called_once()
        mock_vpn_log.assert_called_once()
        
        # Verify both methods sent metrics
        mock_internet_metrics.assert_called_once()
        mock_vpn_metrics.assert_called_once()
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials')
    def test_error_handling_consistency_between_routing_methods(self, mock_vpn_creds, mock_internet_creds):
        """Test that both routing methods handle errors consistently"""
        # Mock authentication failure for both methods
        auth_error = ClientError(
            {'Error': {'Code': 'ResourceNotFoundException'}}, 'GetSecretValue'
        )
        mock_internet_creds.side_effect = auth_error
        mock_vpn_creds.side_effect = auth_error
        
        # Execute both routing methods
        internet_result = internet_lambda_handler(self.internet_event, self.context)
        vpn_result = vpn_lambda_handler(self.vpn_event, self.context)
        
        # Verify both return authentication errors
        self.assertEqual(internet_result['statusCode'], 401)
        self.assertEqual(vpn_result['statusCode'], 401)
        
        # Parse error responses
        internet_error = json.loads(internet_result['body'])
        vpn_error = json.loads(vpn_result['body'])
        
        # Verify error structure consistency
        self.assertEqual(internet_error['error']['code'], 'AUTHENTICATION_FAILED')
        self.assertEqual(vpn_error['error']['code'], 'AUTHENTICATION_FAILED')
        self.assertIn('Failed to retrieve commercial credentials', internet_error['error']['message'])
        self.assertIn('Failed to retrieve commercial credentials', vpn_error['error']['message'])
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials')
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn')
    def test_performance_comparison_between_routing_methods(self, mock_vpn_forward, mock_vpn_creds,
                                                           mock_internet_forward, mock_internet_creds):
        """Test performance comparison between routing methods"""
        # Mock successful credentials
        mock_internet_creds.return_value = {'bedrock_api_key': 'test-key'}
        mock_vpn_creds.return_value = {'bedrock_api_key': 'test-key'}
        
        # Mock successful responses
        mock_response = {
            'body': json.dumps({'content': [{'text': 'Performance test response'}]}),
            'contentType': 'application/json'
        }
        mock_internet_forward.return_value = mock_response
        mock_vpn_forward.return_value = mock_response
        
        # Measure internet routing performance
        internet_start = time.time()
        internet_result = internet_lambda_handler(self.internet_event, self.context)
        internet_end = time.time()
        internet_latency = (internet_end - internet_start) * 1000
        
        # Measure VPN routing performance
        vpn_start = time.time()
        vpn_result = vpn_lambda_handler(self.vpn_event, self.context)
        vpn_end = time.time()
        vpn_latency = (vpn_end - vpn_start) * 1000
        
        # Verify both succeed
        self.assertEqual(internet_result['statusCode'], 200)
        self.assertEqual(vpn_result['statusCode'], 200)
        
        # Log performance comparison
        print(f"\nPerformance Comparison:")
        print(f"Internet routing latency: {internet_latency:.2f}ms")
        print(f"VPN routing latency: {vpn_latency:.2f}ms")
        print(f"Latency difference: {abs(internet_latency - vpn_latency):.2f}ms")
        
        # Verify both methods complete within reasonable time
        self.assertLess(internet_latency, 5000, "Internet routing should complete within 5 seconds")
        self.assertLess(vpn_latency, 5000, "VPN routing should complete within 5 seconds")


if __name__ == '__main__':
    # Create test suite
    test_suite = unittest.TestSuite()
    
    # Add test classes
    test_classes = [
        TestEndToEndInternetRouting,
        TestEndToEndVPNRouting,
        TestEndToEndRoutingComparison
    ]
    
    for test_class in test_classes:
        tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
        test_suite.addTests(tests)
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)
    
    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)