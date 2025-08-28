"""
Unit tests for Internet Lambda function
Tests internet-specific functionality, dual routing features, and error handling
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
from dual_routing_internet_lambda import (
    lambda_handler, detect_routing_method, parse_request,
    get_bedrock_bearer_token, make_bedrock_request,
    get_inference_profile_id
)
from dual_routing_error_handler import (
    NetworkError, AuthenticationError, ValidationError, ServiceError
)

class TestInternetLambdaFunction(unittest.TestCase):
    """Test cases for Internet Lambda function"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'COMMERCIAL_CREDENTIALS_SECRET': 'test-commercial-creds',
            'REQUEST_LOG_TABLE': 'test-request-log-table',
            'ROUTING_METHOD': 'internet'
        })
        self.env_patcher.start()
        
        # Sample API Gateway event for internet routing
        self.internet_event = {
            'httpMethod': 'POST',
            'path': '/v1/bedrock/invoke-model',
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
                    'sourceIp': '192.168.1.100',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/testuser'
                }
            }
        }
        
        # Sample context
        self.context = Mock()
        self.context.aws_request_id = 'test-request-id'
        self.context.function_name = 'test-internet-lambda' 
   
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    def test_detect_routing_method_internet_path(self):
        """Test routing method detection for internet paths"""
        internet_paths = [
            '/v1/bedrock/invoke-model',
            '/v1/bedrock/models',
            '/prod/v1/bedrock/invoke-model',
            '/stage/v1/bedrock/models'
        ]
        
        for path in internet_paths:
            with self.subTest(path=path):
                result = detect_routing_method(path)
                self.assertEqual(result, 'internet')
    
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
    
    def test_parse_request_valid_internet_request(self):
        """Test parsing valid internet request"""
        result = parse_request(self.internet_event)
        
        self.assertEqual(result['modelId'], 'anthropic.claude-3-haiku-20240307-v1:0')
        self.assertEqual(result['contentType'], 'application/json')
        self.assertEqual(result['sourceIP'], '192.168.1.100')
        self.assertEqual(result['routing_method'], 'internet')
        self.assertEqual(result['api_path'], '/v1/bedrock/invoke-model')
        self.assertIn('body', result)
    
    def test_parse_request_missing_model_id(self):
        """Test parsing request with missing modelId"""
        invalid_event = self.internet_event.copy()
        body = json.loads(invalid_event['body'])
        del body['modelId']
        invalid_event['body'] = json.dumps(body)
        
        with self.assertRaises(ValueError) as context:
            parse_request(invalid_event)
        
        self.assertIn('Missing required parameter: modelId', str(context.exception))
    
    def test_parse_request_invalid_json(self):
        """Test parsing request with invalid JSON body"""
        invalid_event = self.internet_event.copy()
        invalid_event['body'] = 'invalid-json'
        
        with self.assertRaises(ValueError) as context:
            parse_request(invalid_event)
        
        self.assertIn('Invalid request format', str(context.exception)) 
   
    @patch('dual_routing_internet_lambda.secrets_client')
    def test_get_bedrock_bearer_token_success(self, mock_secrets_client):
        """Test successful bearer token retrieval"""
        # Mock successful response
        mock_response = {
            'SecretString': json.dumps({
                'bedrock_bearer_token': 'test-bearer-token-12345',
                'region': 'us-east-1'
            })
        }
        mock_secrets_client.get_secret_value.return_value = mock_response
        
        result = get_bedrock_bearer_token()
        
        self.assertEqual(result, 'test-bearer-token-12345')
        mock_secrets_client.get_secret_value.assert_called_once()
    
    @patch.dict(os.environ, {'AWS_BEARER_TOKEN_BEDROCK': 'env-bearer-token-123'})
    def test_get_bedrock_bearer_token_from_env(self):
        """Test bearer token retrieval from environment variable"""
        result = get_bedrock_bearer_token()
        
        self.assertEqual(result, 'env-bearer-token-123')
    
    @patch('dual_routing_internet_lambda.secrets_client')
    def test_get_bedrock_bearer_token_failure(self, mock_secrets_client):
        """Test bearer token retrieval failure"""
        from botocore.exceptions import ClientError
        mock_secrets_client.get_secret_value.side_effect = ClientError(
            {'Error': {'Code': 'ResourceNotFoundException'}}, 'GetSecretValue'
        )
        
        with self.assertRaises(Exception) as context:
            get_bedrock_bearer_token()
        
        self.assertIn('Unable to retrieve Bedrock bearer token', str(context.exception))
    
    def test_create_bedrock_session_success(self):
        """Test successful Bedrock session creation"""
        credentials = {
            'aws_access_key_id': 'AKIA12345',
            'aws_secret_access_key': 'secret12345',
            'region': 'us-east-1'
        }
        
        with patch('dual_routing_internet_lambda.boto3.Session') as mock_session:
            mock_session_instance = Mock()
            mock_session.return_value = mock_session_instance
            
            result = create_bedrock_session(credentials)
            
            mock_session.assert_called_once_with(
                aws_access_key_id='AKIA12345',
                aws_secret_access_key='secret12345',
                region_name='us-east-1'
            )
            self.assertEqual(result, mock_session_instance)
    
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
    
    @patch('dual_routing_internet_lambda.urllib.request.urlopen')
    def test_forward_with_api_key_success(self, mock_urlopen):
        """Test successful internet routing with API key"""
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
        
        result = forward_to_bedrock(commercial_creds, request_data)
        
        self.assertIn('body', result)
        self.assertEqual(result['routing_method'], 'internet')
        self.assertIn('endpoint_used', result)
    
    @patch('dual_routing_internet_lambda.urllib.request.urlopen')
    def test_forward_with_api_key_http_error(self, mock_urlopen):
        """Test internet routing with API key HTTP error"""
        from urllib.error import HTTPError
        
        # Mock HTTP error
        mock_error = HTTPError(
            url='test-url', code=403, msg='Forbidden', hdrs={}, fp=Mock()
        )
        mock_error.read.return_value = b'Access denied'
        mock_urlopen.side_effect = mock_error
        
        commercial_creds = {'bedrock_api_key': 'invalid-api-key'}
        request_data = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'body': {'messages': [{'role': 'user', 'content': 'test'}]}
        }
        
        with self.assertRaises(Exception) as context:
            forward_to_bedrock(commercial_creds, request_data)
        
        self.assertIn('Access denied', str(context.exception))
    
    @patch('dual_routing_internet_lambda.create_bedrock_session')
    def test_forward_with_aws_credentials_success(self, mock_create_session):
        """Test successful internet routing with AWS credentials"""
        # Mock AWS session and Bedrock client
        mock_session = Mock()
        mock_bedrock_client = Mock()
        mock_create_session.return_value = mock_session
        mock_session.client.return_value = mock_bedrock_client
        
        # Mock successful Bedrock response
        mock_response_body = Mock()
        mock_response_body.read.return_value = json.dumps({
            'content': [{'text': 'Test response'}]
        }).encode('utf-8')
        
        mock_bedrock_client.invoke_model.return_value = {
            'body': mock_response_body,
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
        
        result = forward_to_bedrock(commercial_creds, request_data)
        
        self.assertEqual(result['routing_method'], 'internet')
        self.assertTrue(result['aws_credentials_used'])
    
    @patch('dual_routing_internet_lambda.log_request')
    @patch('dual_routing_internet_lambda.send_custom_metrics')
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    def test_lambda_handler_successful_internet_request(self, mock_get_creds, mock_forward, 
                                                        mock_metrics, mock_log):
        """Test successful Internet Lambda handler execution"""
        # Mock successful credential retrieval
        mock_get_creds.return_value = {'bedrock_api_key': 'test-key'}
        
        # Mock successful Bedrock forwarding
        mock_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'Test response'}]}),
            'contentType': 'application/json'
        }
        
        result = lambda_handler(self.internet_event, self.context)
        
        self.assertEqual(result['statusCode'], 200)
        self.assertIn('X-Routing-Method', result['headers'])
        self.assertEqual(result['headers']['X-Routing-Method'], 'internet')
        
        # Verify mocks were called
        mock_get_creds.assert_called_once()
        mock_forward.assert_called_once()
        mock_metrics.assert_called_once()
        mock_log.assert_called_once()
    
    def test_lambda_handler_invalid_routing_path(self):
        """Test Lambda handler with invalid routing path (VPN path to Internet Lambda)"""
        # Create event with VPN path (should be rejected by Internet Lambda)
        vpn_event = self.internet_event.copy()
        vpn_event['path'] = '/v1/vpn/bedrock/invoke-model'
        
        result = lambda_handler(vpn_event, self.context)
        
        self.assertEqual(result['statusCode'], 400)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VALIDATION_ERROR')
        self.assertIn('internet routing requests', body['error']['message'])
    
    def test_lambda_handler_get_request_routing_info(self):
        """Test Lambda handler GET request for routing info"""
        get_event = self.internet_event.copy()
        get_event['httpMethod'] = 'GET'
        
        with patch('dual_routing_internet_lambda.get_routing_info') as mock_get_info:
            mock_get_info.return_value = {
                'statusCode': 200,
                'body': json.dumps({'message': 'Internet routing info'})
            }
            
            result = lambda_handler(get_event, self.context)
            
            self.assertEqual(result['statusCode'], 200)
            mock_get_info.assert_called_once()
    
    def test_lambda_handler_get_request_models(self):
        """Test Lambda handler GET request for models"""
        get_event = self.internet_event.copy()
        get_event['httpMethod'] = 'GET'
        get_event['path'] = '/v1/bedrock/models'
        
        with patch('dual_routing_internet_lambda.get_available_models') as mock_get_models:
            mock_get_models.return_value = {
                'statusCode': 200,
                'body': json.dumps({'models': []})
            }
            
            result = lambda_handler(get_event, self.context)
            
            self.assertEqual(result['statusCode'], 200)
            mock_get_models.assert_called_once()
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    def test_lambda_handler_authentication_failure(self, mock_get_creds):
        """Test Lambda handler with authentication failure"""
        # Mock authentication failure
        mock_get_creds.side_effect = Exception('Invalid credentials')
        
        result = lambda_handler(self.internet_event, self.context)
        
        self.assertEqual(result['statusCode'], 401)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'AUTHENTICATION_FAILED')
        self.assertIn('Failed to retrieve commercial credentials', body['error']['message'])
    
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    def test_lambda_handler_network_error(self, mock_get_creds, mock_forward):
        """Test Lambda handler with network error"""
        # Mock successful credentials but network failure
        mock_get_creds.return_value = {'bedrock_api_key': 'test-key'}
        mock_forward.side_effect = Exception('Connection timeout')
        
        result = lambda_handler(self.internet_event, self.context)
        
        self.assertEqual(result['statusCode'], 502)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'NETWORK_ERROR')
        self.assertIn('Network error occurred', body['error']['message'])

class TestInternetLambdaAdvancedFeatures(unittest.TestCase):
    """Advanced test cases for Internet Lambda function features"""
    
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
    
    @patch('dual_routing_internet_lambda.dynamodb')
    def test_log_request_success(self, mock_dynamodb):
        """Test successful request logging to DynamoDB"""
        from dual_routing_internet_lambda import log_request
        
        # Mock DynamoDB table
        mock_table = Mock()
        mock_dynamodb.Table.return_value = mock_table
        
        request_data = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'userArn': 'arn:aws-us-gov:iam::123456789012:user/testuser',
            'sourceIP': '192.168.1.100',
            'api_path': '/v1/bedrock/invoke-model'
        }
        
        response = {
            'body': json.dumps({'content': [{'text': 'test response'}]}),
            'endpoint_used': 'https://bedrock-runtime.us-east-1.amazonaws.com',
            'aws_credentials_used': True
        }
        
        # Call log_request
        log_request('test-request-id', request_data, response, 150, True)
        
        # Verify DynamoDB put_item was called
        mock_table.put_item.assert_called_once()
        call_args = mock_table.put_item.call_args[1]['Item']
        
        self.assertEqual(call_args['requestId'], 'test-request-id')
        self.assertEqual(call_args['routingMethod'], 'internet')
        self.assertEqual(call_args['modelId'], 'anthropic.claude-3-haiku-20240307-v1:0')
        self.assertEqual(call_args['latency'], 150)
        self.assertTrue(call_args['success'])
        self.assertEqual(call_args['endpointUsed'], 'https://bedrock-runtime.us-east-1.amazonaws.com')
        self.assertTrue(call_args['awsCredentialsUsed'])
    
    @patch('dual_routing_internet_lambda.dynamodb')
    def test_log_request_failure(self, mock_dynamodb):
        """Test request logging for failed requests"""
        from dual_routing_internet_lambda import log_request
        
        # Mock DynamoDB table
        mock_table = Mock()
        mock_dynamodb.Table.return_value = mock_table
        
        request_data = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'userArn': 'arn:aws-us-gov:iam::123456789012:user/testuser',
            'sourceIP': '192.168.1.100',
            'api_path': '/v1/bedrock/invoke-model'
        }
        
        # Call log_request for failed request
        log_request('test-request-id', request_data, None, 5000, False, 'Network timeout')
        
        # Verify DynamoDB put_item was called
        mock_table.put_item.assert_called_once()
        call_args = mock_table.put_item.call_args[1]['Item']
        
        self.assertEqual(call_args['requestId'], 'test-request-id')
        self.assertFalse(call_args['success'])
        self.assertEqual(call_args['statusCode'], 500)
        self.assertEqual(call_args['errorMessage'], 'Network timeout')
        self.assertEqual(call_args['latency'], 5000)
    
    @patch('dual_routing_internet_lambda.boto3.client')
    def test_send_custom_metrics_success(self, mock_boto3_client):
        """Test successful custom metrics sending"""
        from dual_routing_internet_lambda import send_custom_metrics
        
        # Mock CloudWatch client
        mock_cloudwatch = Mock()
        mock_boto3_client.return_value = mock_cloudwatch
        
        # Call send_custom_metrics
        send_custom_metrics('test-request-id', 200, True)
        
        # Verify CloudWatch put_metric_data was called
        mock_cloudwatch.put_metric_data.assert_called_once()
        call_args = mock_cloudwatch.put_metric_data.call_args[1]
        
        self.assertEqual(call_args['Namespace'], 'CrossPartition/DualRouting')
        self.assertEqual(len(call_args['MetricData']), 2)  # Two metrics
        
        # Check metrics data
        metrics = call_args['MetricData']
        metric_names = [metric['MetricName'] for metric in metrics]
        self.assertIn('CrossPartitionRequests', metric_names)
        self.assertIn('CrossPartitionLatency', metric_names)
    
    @patch('dual_routing_internet_lambda.create_bedrock_session')
    def test_get_available_models_success(self, mock_create_session):
        """Test successful model listing via internet"""
        from dual_routing_internet_lambda import get_available_models
        
        # Mock AWS session and Bedrock client
        mock_session = Mock()
        mock_bedrock_client = Mock()
        mock_create_session.return_value = mock_session
        mock_session.client.return_value = mock_bedrock_client
        
        # Mock Bedrock list_foundation_models response
        mock_bedrock_client.list_foundation_models.return_value = {
            'modelSummaries': [
                {
                    'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                    'modelName': 'Claude 3 Haiku',
                    'providerName': 'Anthropic',
                    'inputModalities': ['TEXT'],
                    'outputModalities': ['TEXT'],
                    'responseStreamingSupported': True,
                    'customizationsSupported': [],
                    'inferenceTypesSupported': ['ON_DEMAND']
                }
            ]
        }
        
        # Mock get_commercial_credentials
        with patch('dual_routing_internet_lambda.get_commercial_credentials') as mock_get_creds:
            mock_get_creds.return_value = {
                'aws_access_key_id': 'test-key',
                'aws_secret_access_key': 'test-secret',
                'region': 'us-east-1'
            }
            
            event = {'path': '/v1/bedrock/models'}
            result = get_available_models(event, self.context)
        
        self.assertEqual(result['statusCode'], 200)
        body = json.loads(result['body'])
        self.assertEqual(body['totalModels'], 1)
        self.assertEqual(len(body['models']), 1)
        self.assertEqual(body['models'][0]['modelId'], 'anthropic.claude-3-haiku-20240307-v1:0')
        self.assertEqual(body['source']['routing_method'], 'internet')
    
    def test_get_routing_info_success(self):
        """Test successful routing info retrieval"""
        from dual_routing_internet_lambda import get_routing_info
        
        event = {
            'requestContext': {
                'identity': {
                    'sourceIp': '192.168.1.100'
                },
                'domainName': 'api.example.com'
            },
            'headers': {
                'User-Agent': 'test-client/1.0'
            }
        }
        
        result = get_routing_info(event, self.context)
        
        self.assertEqual(result['statusCode'], 200)
        body = json.loads(result['body'])
        
        self.assertEqual(body['routing']['method'], 'internet')
        self.assertEqual(body['routing']['source']['partition'], 'AWS GovCloud')
        self.assertEqual(body['routing']['destination']['partition'], 'AWS Commercial')
        self.assertEqual(body['routing']['destination']['access_method'], 'Internet')
        self.assertEqual(body['request_info']['source_ip'], '192.168.1.100')
        self.assertEqual(body['request_info']['user_agent'], 'test-client/1.0')
    
    @patch('dual_routing_internet_lambda.create_bedrock_session')
    def test_forward_with_aws_credentials_inference_profile_retry(self, mock_create_session):
        """Test AWS credentials forwarding with inference profile retry"""
        from dual_routing_internet_lambda import forward_to_bedrock
        
        # Mock AWS session and Bedrock client
        mock_session = Mock()
        mock_bedrock_client = Mock()
        mock_create_session.return_value = mock_session
        mock_session.client.return_value = mock_bedrock_client
        
        # Mock first call failure (requires inference profile)
        mock_bedrock_client.invoke_model.side_effect = [
            Exception('Model requires on-demand throughput via inference profile'),
            {
                'body': Mock(read=lambda: json.dumps({
                    'content': [{'text': 'Success with inference profile'}]
                }).encode('utf-8')),
                'contentType': 'application/json'
            }
        ]
        
        commercial_creds = {
            'aws_access_key_id': 'test-access-key',
            'aws_secret_access_key': 'test-secret-key',
            'region': 'us-east-1'
        }
        request_data = {
            'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
            'body': json.dumps({'messages': [{'role': 'user', 'content': 'test'}]})
        }
        
        result = forward_to_bedrock(commercial_creds, request_data)
        
        # Verify retry with inference profile
        self.assertEqual(mock_bedrock_client.invoke_model.call_count, 2)
        self.assertEqual(result['routing_method'], 'internet')
        self.assertTrue(result['aws_credentials_used'])
        self.assertEqual(result['inference_profile_used'], 'us.anthropic.claude-3-haiku-20240307-v1:0')
    
    def test_forward_with_api_key_base64_decoding(self):
        """Test API key forwarding with base64 decoding"""
        from dual_routing_internet_lambda import forward_with_api_key
        import base64
        
        # Create a base64 encoded API key
        original_key = 'AKIA12345:bedrock-api-key-secret'
        encoded_key = base64.b64encode(original_key.encode('utf-8')).decode('utf-8')
        
        with patch('dual_routing_internet_lambda.urllib.request.urlopen') as mock_urlopen:
            # Mock successful HTTP response
            mock_response = Mock()
            mock_response.read.return_value = json.dumps({
                'content': [{'text': 'Test response'}]
            }).encode('utf-8')
            mock_response.headers = {'content-type': 'application/json'}
            mock_urlopen.return_value.__enter__.return_value = mock_response
            
            result = forward_with_api_key(encoded_key, 'test-model', '{"test": "body"}')
            
            self.assertEqual(result['routing_method'], 'internet')
            self.assertIn('endpoint_used', result)
    
    @patch('dual_routing_internet_lambda.urllib.request.urlopen')
    def test_forward_with_api_key_various_http_errors(self, mock_urlopen):
        """Test API key forwarding with various HTTP error codes"""
        from dual_routing_internet_lambda import forward_with_api_key
        from urllib.error import HTTPError
        
        error_test_cases = [
            (400, 'Bad Request', 'Invalid request parameters'),
            (403, 'Forbidden', 'Access denied to commercial Bedrock'),
            (429, 'Too Many Requests', 'Request throttled by commercial Bedrock'),
            (500, 'Internal Server Error', 'Commercial Bedrock error via internet')
        ]
        
        for status_code, msg, expected_message in error_test_cases:
            with self.subTest(status_code=status_code):
                # Mock HTTP error
                mock_error = HTTPError(
                    url='test-url', code=status_code, msg=msg, hdrs={}, fp=Mock()
                )
                mock_error.read.return_value = f'Error {status_code}'.encode('utf-8')
                mock_urlopen.side_effect = mock_error
                
                with self.assertRaises(Exception) as context:
                    forward_with_api_key('test-key', 'test-model', '{"test": "body"}')
                
                self.assertIn(expected_message, str(context.exception))


class TestInternetLambdaErrorHandling(unittest.TestCase):
    """Test cases for Internet Lambda error handling"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.env_patcher = patch.dict(os.environ, {
            'COMMERCIAL_CREDENTIALS_SECRET': 'test-commercial-creds',
            'REQUEST_LOG_TABLE': 'test-request-log-table'
        })
        self.env_patcher.start()
        
        self.context = Mock()
        self.context.aws_request_id = 'test-request-id'
        
        # Sample event
        self.test_event = {
            'httpMethod': 'POST',
            'path': '/v1/bedrock/invoke-model',
            'body': json.dumps({
                'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                'body': {'messages': [{'role': 'user', 'content': 'test'}]}
            }),
            'requestContext': {
                'identity': {
                    'sourceIp': '192.168.1.100',
                    'userArn': 'arn:aws-us-gov:iam::123456789012:user/testuser'
                }
            }
        }
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    def test_lambda_handler_service_error(self, mock_get_creds, mock_forward):
        """Test Lambda handler with service error"""
        from dual_routing_internet_lambda import lambda_handler
        
        # Mock successful credentials but service failure
        mock_get_creds.return_value = {'bedrock_api_key': 'test-key'}
        mock_forward.side_effect = Exception('Internal service error')
        
        result = lambda_handler(self.test_event, self.context)
        
        self.assertEqual(result['statusCode'], 503)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'SERVICE_ERROR')
        self.assertIn('Failed to forward request', body['error']['message'])
    
    def test_lambda_handler_missing_body(self):
        """Test Lambda handler with missing request body"""
        from dual_routing_internet_lambda import lambda_handler
        
        invalid_event = self.test_event.copy()
        del invalid_event['body']
        
        result = lambda_handler(invalid_event, self.context)
        
        self.assertEqual(result['statusCode'], 400)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VALIDATION_ERROR')
        self.assertIn('Missing request body', body['error']['message'])
    
    def test_lambda_handler_invalid_json_body(self):
        """Test Lambda handler with invalid JSON in body"""
        from dual_routing_internet_lambda import lambda_handler
        
        invalid_event = self.test_event.copy()
        invalid_event['body'] = 'invalid-json-content'
        
        result = lambda_handler(invalid_event, self.context)
        
        self.assertEqual(result['statusCode'], 400)
        body = json.loads(result['body'])
        self.assertEqual(body['error']['code'], 'VALIDATION_ERROR')
        self.assertIn('Invalid request format', body['error']['message'])
    
    @patch('dual_routing_internet_lambda.log_request')
    def test_lambda_handler_logging_failure_handling(self, mock_log_request):
        """Test Lambda handler handles logging failures gracefully"""
        from dual_routing_internet_lambda import lambda_handler
        
        # Mock logging failure
        mock_log_request.side_effect = Exception('DynamoDB connection failed')
        
        # Mock other dependencies to succeed
        with patch('dual_routing_internet_lambda.get_commercial_credentials') as mock_get_creds, \
             patch('dual_routing_internet_lambda.forward_to_bedrock') as mock_forward, \
             patch('dual_routing_internet_lambda.send_custom_metrics') as mock_metrics:
            
            mock_get_creds.return_value = {'bedrock_api_key': 'test-key'}
            mock_forward.return_value = {
                'body': json.dumps({'content': [{'text': 'test'}]}),
                'contentType': 'application/json'
            }
            
            # Should still succeed despite logging failure
            result = lambda_handler(self.test_event, self.context)
            
            self.assertEqual(result['statusCode'], 200)
            # Verify other functions were still called
            mock_get_creds.assert_called_once()
            mock_forward.assert_called_once()
            mock_metrics.assert_called_once()


if __name__ == '__main__':
    # Create test suite
    test_suite = unittest.TestSuite()
    
    # Add test classes
    test_classes = [
        TestInternetLambdaFunction,
        TestInternetLambdaAdvancedFeatures,
        TestInternetLambdaErrorHandling
    ]
    
    for test_class in test_classes:
        tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
        test_suite.addTests(tests)
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)
    
    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)