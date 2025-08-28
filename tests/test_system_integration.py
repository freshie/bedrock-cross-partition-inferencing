"""
System integration tests for dual routing architecture
Tests complete system integration including API Gateway, Lambda functions, and external services
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

# Add lambda directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lambda'))


class TestSystemIntegration(unittest.TestCase):
    """System integration tests for the complete dual routing architecture"""
    
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
        
        # System integration test scenarios
        self.system_test_scenarios = [
            {
                'name': 'high_volume_internet_routing',
                'description': 'High volume requests through internet routing',
                'routing_method': 'internet',
                'request_count': 10,
                'concurrent': False
            },
            {
                'name': 'high_volume_vpn_routing',
                'description': 'High volume requests through VPN routing',
                'routing_method': 'vpn',
                'request_count': 10,
                'concurrent': False
            },
            {
                'name': 'mixed_routing_load',
                'description': 'Mixed load across both routing methods',
                'routing_method': 'mixed',
                'request_count': 20,
                'concurrent': True
            },
            {
                'name': 'error_recovery_testing',
                'description': 'Error recovery and resilience testing',
                'routing_method': 'both',
                'request_count': 5,
                'concurrent': False,
                'inject_errors': True
            }
        ]
        
        self.context = Mock()
        self.context.aws_request_id = 'system-integration-test'
        self.context.function_name = 'system-integration-test'
        self.context.remaining_time_in_millis = lambda: 30000
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    def _create_test_event(self, routing_method, request_id=None):
        """Create a test event for the specified routing method"""
        if request_id is None:
            request_id = str(uuid.uuid4())
        
        base_path = '/v1/vpn/bedrock/invoke-model' if routing_method == 'vpn' else '/v1/bedrock/invoke-model'
        
        return {
            'httpMethod': 'POST',
            'path': base_path,
            'headers': {
                'Content-Type': 'application/json',
                'X-API-Key': f'test-api-key-{routing_method}',
                'X-Request-ID': request_id
            },
            'body': json.dumps({
                'modelId': 'anthropic.claude-3-haiku-20240307-v1:0',
                'body': {
                    'messages': [
                        {
                            'role': 'user',
                            'content': f'System integration test message for {routing_method} routing - Request ID: {request_id}'
                        }
                    ],
                    'max_tokens': 50
                }
            }),
            'requestContext': {
                'requestId': request_id,
                'identity': {
                    'sourceIp': '10.0.1.100' if routing_method == 'vpn' else '203.0.113.1',
                    'userArn': f'arn:aws-us-gov:iam::123456789012:user/system-test-{routing_method}'
                }
            }
        }
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_internet_lambda.log_request')
    @patch('dual_routing_internet_lambda.send_custom_metrics')
    def test_high_volume_internet_routing(self, mock_internet_metrics, mock_internet_log, 
                                         mock_internet_forward, mock_internet_creds):
        """Test high volume requests through internet routing"""
        from dual_routing_internet_lambda import lambda_handler as internet_handler
        
        # Mock successful responses
        mock_internet_creds.return_value = {'bedrock_api_key': 'test-key'}
        mock_internet_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'System test response'}]}),
            'contentType': 'application/json'
        }
        
        # Execute high volume test
        request_count = 10
        results = []
        start_time = time.time()
        
        for i in range(request_count):
            event = self._create_test_event('internet', f'high-volume-internet-{i}')
            result = internet_handler(event, self.context)
            results.append(result)
        
        end_time = time.time()
        total_time = end_time - start_time
        
        # Verify all requests succeeded
        for i, result in enumerate(results):
            with self.subTest(request=i):
                self.assertEqual(result['statusCode'], 200)
                self.assertEqual(result['headers']['X-Routing-Method'], 'internet')
        
        # Verify performance metrics
        avg_time_per_request = total_time / request_count
        self.assertLess(avg_time_per_request, 1.0, "Average time per request should be under 1 second")
        
        # Verify all requests were logged and metrics sent
        self.assertEqual(mock_internet_log.call_count, request_count)
        self.assertEqual(mock_internet_metrics.call_count, request_count)
        
        print(f"High volume internet routing: {request_count} requests in {total_time:.2f}s "
              f"(avg: {avg_time_per_request:.3f}s per request)")
    
    @patch('dual_routing_vpn_lambda.get_commercial_credentials')
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn')
    @patch('dual_routing_vpn_lambda.log_request')
    @patch('dual_routing_vpn_lambda.send_custom_metrics')
    def test_high_volume_vpn_routing(self, mock_vpn_metrics, mock_vpn_log, 
                                    mock_vpn_forward, mock_vpn_creds):
        """Test high volume requests through VPN routing"""
        from dual_routing_vpn_lambda import lambda_handler as vpn_handler
        
        # Mock successful responses
        mock_vpn_creds.return_value = {'aws_access_key_id': 'test', 'aws_secret_access_key': 'test'}
        mock_vpn_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'VPN system test response'}]}),
            'contentType': 'application/json'
        }
        
        # Execute high volume test
        request_count = 10
        results = []
        start_time = time.time()
        
        for i in range(request_count):
            event = self._create_test_event('vpn', f'high-volume-vpn-{i}')
            result = vpn_handler(event, self.context)
            results.append(result)
        
        end_time = time.time()
        total_time = end_time - start_time
        
        # Verify all requests succeeded
        for i, result in enumerate(results):
            with self.subTest(request=i):
                self.assertEqual(result['statusCode'], 200)
                self.assertEqual(result['headers']['X-Routing-Method'], 'vpn')
        
        # Verify performance metrics
        avg_time_per_request = total_time / request_count
        self.assertLess(avg_time_per_request, 1.0, "Average time per request should be under 1 second")
        
        # Verify all requests were logged and metrics sent
        self.assertEqual(mock_vpn_log.call_count, request_count)
        self.assertEqual(mock_vpn_metrics.call_count, request_count)
        
        print(f"High volume VPN routing: {request_count} requests in {total_time:.2f}s "
              f"(avg: {avg_time_per_request:.3f}s per request)")
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_internet_lambda.log_request')
    @patch('dual_routing_internet_lambda.send_custom_metrics')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials')
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn')
    @patch('dual_routing_vpn_lambda.log_request')
    @patch('dual_routing_vpn_lambda.send_custom_metrics')
    def test_mixed_routing_load(self, mock_vpn_metrics, mock_vpn_log, mock_vpn_forward, mock_vpn_creds,
                               mock_internet_metrics, mock_internet_log, mock_internet_forward, mock_internet_creds):
        """Test mixed load across both routing methods"""
        from dual_routing_internet_lambda import lambda_handler as internet_handler
        from dual_routing_vpn_lambda import lambda_handler as vpn_handler
        
        # Mock successful responses for both methods
        mock_internet_creds.return_value = {'bedrock_api_key': 'test-key'}
        mock_internet_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'Internet response'}]}),
            'contentType': 'application/json'
        }
        mock_vpn_creds.return_value = {'aws_access_key_id': 'test', 'aws_secret_access_key': 'test'}
        mock_vpn_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'VPN response'}]}),
            'contentType': 'application/json'
        }
        
        # Execute mixed load test
        total_requests = 20
        internet_requests = total_requests // 2
        vpn_requests = total_requests - internet_requests
        
        results = []
        start_time = time.time()
        
        # Alternate between internet and VPN requests
        for i in range(total_requests):
            if i % 2 == 0:
                event = self._create_test_event('internet', f'mixed-internet-{i}')
                result = internet_handler(event, self.context)
            else:
                event = self._create_test_event('vpn', f'mixed-vpn-{i}')
                result = vpn_handler(event, self.context)
            results.append(result)
        
        end_time = time.time()
        total_time = end_time - start_time
        
        # Verify all requests succeeded
        internet_success_count = 0
        vpn_success_count = 0
        
        for i, result in enumerate(results):
            with self.subTest(request=i):
                self.assertEqual(result['statusCode'], 200)
                if result['headers']['X-Routing-Method'] == 'internet':
                    internet_success_count += 1
                else:
                    vpn_success_count += 1
        
        # Verify balanced load distribution
        self.assertEqual(internet_success_count, internet_requests)
        self.assertEqual(vpn_success_count, vpn_requests)
        
        # Verify performance metrics
        avg_time_per_request = total_time / total_requests
        self.assertLess(avg_time_per_request, 1.0, "Average time per request should be under 1 second")
        
        print(f"Mixed routing load: {total_requests} requests in {total_time:.2f}s "
              f"(Internet: {internet_success_count}, VPN: {vpn_success_count}, "
              f"avg: {avg_time_per_request:.3f}s per request)")
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials')
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn')
    def test_error_recovery_and_resilience(self, mock_vpn_forward, mock_vpn_creds,
                                          mock_internet_forward, mock_internet_creds):
        """Test error recovery and system resilience"""
        from dual_routing_internet_lambda import lambda_handler as internet_handler
        from dual_routing_vpn_lambda import lambda_handler as vpn_handler
        
        # Test scenario 1: Authentication failure recovery
        mock_internet_creds.side_effect = [
            Exception('Auth failure'),  # First call fails
            {'bedrock_api_key': 'test-key'}  # Second call succeeds
        ]
        mock_internet_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'Recovery response'}]}),
            'contentType': 'application/json'
        }
        
        # First request should fail
        event1 = self._create_test_event('internet', 'error-recovery-1')
        result1 = internet_handler(event1, self.context)
        self.assertEqual(result1['statusCode'], 401)  # Authentication error
        
        # Second request should succeed (simulating recovery)
        event2 = self._create_test_event('internet', 'error-recovery-2')
        result2 = internet_handler(event2, self.context)
        self.assertEqual(result2['statusCode'], 200)  # Success after recovery
        
        # Test scenario 2: VPN endpoint failure handling
        mock_vpn_creds.return_value = {'aws_access_key_id': 'test', 'aws_secret_access_key': 'test'}
        mock_vpn_forward.side_effect = Exception('VPC endpoint connection failed')
        
        event3 = self._create_test_event('vpn', 'vpn-error-test')
        result3 = vpn_handler(event3, self.context)
        self.assertEqual(result3['statusCode'], 502)  # Network error
        
        # Verify error responses contain proper error information
        error_body = json.loads(result3['body'])
        self.assertIn('error', error_body)
        self.assertIn('code', error_body['error'])
        
        print("Error recovery and resilience testing completed successfully")
    
    def test_system_configuration_validation(self):
        """Test system configuration and environment validation"""
        # Verify required environment variables are set
        required_env_vars = [
            'COMMERCIAL_CREDENTIALS_SECRET',
            'REQUEST_LOG_TABLE',
            'VPC_ENDPOINT_BEDROCK',
            'VPC_ENDPOINT_SECRETS',
            'VPC_ENDPOINT_DYNAMODB'
        ]
        
        for env_var in required_env_vars:
            with self.subTest(env_var=env_var):
                self.assertIn(env_var, os.environ, f"Required environment variable {env_var} not set")
                self.assertNotEqual(os.environ[env_var], '', f"Environment variable {env_var} is empty")
        
        # Verify Lambda function imports work correctly
        try:
            from dual_routing_internet_lambda import lambda_handler as internet_handler
            from dual_routing_vpn_lambda import lambda_handler as vpn_handler
            from dual_routing_error_handler import ErrorHandler
            
            self.assertTrue(callable(internet_handler), "Internet Lambda handler should be callable")
            self.assertTrue(callable(vpn_handler), "VPN Lambda handler should be callable")
            self.assertTrue(callable(ErrorHandler), "ErrorHandler should be callable")
            
        except ImportError as e:
            self.fail(f"Failed to import required modules: {str(e)}")
        
        print("System configuration validation completed successfully")
    
    @patch('dual_routing_internet_lambda.get_commercial_credentials')
    @patch('dual_routing_internet_lambda.forward_to_bedrock')
    @patch('dual_routing_vpn_lambda.get_commercial_credentials')
    @patch('dual_routing_vpn_lambda.forward_to_bedrock_via_vpn')
    def test_request_tracing_and_correlation(self, mock_vpn_forward, mock_vpn_creds,
                                           mock_internet_forward, mock_internet_creds):
        """Test request tracing and correlation across the system"""
        from dual_routing_internet_lambda import lambda_handler as internet_handler
        from dual_routing_vpn_lambda import lambda_handler as vpn_handler
        
        # Mock successful responses
        mock_internet_creds.return_value = {'bedrock_api_key': 'test-key'}
        mock_internet_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'Traced response'}]}),
            'contentType': 'application/json'
        }
        mock_vpn_creds.return_value = {'aws_access_key_id': 'test', 'aws_secret_access_key': 'test'}
        mock_vpn_forward.return_value = {
            'body': json.dumps({'content': [{'text': 'VPN traced response'}]}),
            'contentType': 'application/json'
        }
        
        # Test request correlation
        correlation_id = 'trace-test-12345'
        
        # Internet request with correlation ID
        internet_event = self._create_test_event('internet', correlation_id)
        internet_result = internet_handler(internet_event, self.context)
        
        # VPN request with same correlation ID
        vpn_event = self._create_test_event('vpn', correlation_id)
        vpn_result = vpn_handler(vpn_event, self.context)
        
        # Verify both requests succeeded
        self.assertEqual(internet_result['statusCode'], 200)
        self.assertEqual(vpn_result['statusCode'], 200)
        
        # Verify request IDs are preserved in headers
        self.assertIn('X-Request-ID', internet_result['headers'])
        self.assertIn('X-Request-ID', vpn_result['headers'])
        
        # Verify routing method headers are correct
        self.assertEqual(internet_result['headers']['X-Routing-Method'], 'internet')
        self.assertEqual(vpn_result['headers']['X-Routing-Method'], 'vpn')
        
        print(f"Request tracing validation completed for correlation ID: {correlation_id}")
    
    def test_system_health_check(self):
        """Test system health check functionality"""
        from dual_routing_internet_lambda import get_routing_info
        from dual_routing_vpn_lambda import get_routing_info as get_vpn_routing_info
        
        # Test internet routing health check
        internet_health_event = {
            'httpMethod': 'GET',
            'path': '/v1/bedrock',
            'headers': {},
            'requestContext': {
                'identity': {'sourceIp': '203.0.113.1'}
            }
        }
        
        internet_health_result = get_routing_info(internet_health_event, self.context)
        self.assertEqual(internet_health_result['statusCode'], 200)
        
        internet_health_body = json.loads(internet_health_result['body'])
        self.assertEqual(internet_health_body['status'], 'operational')
        self.assertEqual(internet_health_body['routing']['method'], 'internet')
        
        # Test VPN routing health check
        vpn_health_event = {
            'httpMethod': 'GET',
            'path': '/v1/vpn/bedrock',
            'headers': {},
            'requestContext': {
                'identity': {'sourceIp': '10.0.1.100'}
            }
        }
        
        vpn_health_result = get_vpn_routing_info(vpn_health_event, self.context)
        self.assertEqual(vpn_health_result['statusCode'], 200)
        
        vpn_health_body = json.loads(vpn_health_result['body'])
        self.assertEqual(vpn_health_body['status'], 'operational')
        self.assertEqual(vpn_health_body['routing']['method'], 'vpn')
        
        print("System health check validation completed successfully")


if __name__ == '__main__':
    # Create test suite
    test_suite = unittest.TestSuite()
    
    # Add test class
    tests = unittest.TestLoader().loadTestsFromTestCase(TestSystemIntegration)
    test_suite.addTests(tests)
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)
    
    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)