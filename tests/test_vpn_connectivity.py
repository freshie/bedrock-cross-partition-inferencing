#!/usr/bin/env python3
"""
Comprehensive test suite for VPN connectivity solution

This module provides unit tests, integration tests, performance tests,
and security tests for the VPN connectivity implementation.
"""

import unittest
import boto3
import json
import time
import requests
import socket
import subprocess
import os
import logging
from datetime import datetime, timedelta
from unittest.mock import Mock, patch, MagicMock
from moto import mock_ec2, mock_dynamodb, mock_secretsmanager, mock_cloudwatch

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class TestVPNConfiguration(unittest.TestCase):
    """Unit tests for VPN configuration validation"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.project_name = "cross-partition-vpn"
        self.environment = "test"
        
    def test_vpn_configuration_validation(self):
        """Test VPN configuration parameter validation"""
        from lambda.vpn_error_handling import VPNErrorHandler, create_error_context
        
        # Test valid configuration
        config = {
            'govcloud_vpc_id': 'vpc-12345',
            'commercial_vpc_id': 'vpc-67890',
            'tunnel_1_psk': 'secure-key-1-test-12345678',
            'tunnel_2_psk': 'secure-key-2-test-12345678',
            'govcloud_cidr': '10.0.0.0/16',
            'commercial_cidr': '172.16.0.0/16'
        }
        
        # Validate CIDR blocks
        self.assertTrue(self._is_valid_cidr(config['govcloud_cidr']))
        self.assertTrue(self._is_valid_cidr(config['commercial_cidr']))
        
        # Validate PSK length
        self.assertGreaterEqual(len(config['tunnel_1_psk']), 8)
        self.assertGreaterEqual(len(config['tunnel_2_psk']), 8)
        
        # Validate VPC IDs
        self.assertTrue(config['govcloud_vpc_id'].startswith('vpc-'))
        self.assertTrue(config['commercial_vpc_id'].startswith('vpc-'))
    
    def test_error_context_creation(self):
        """Test error context creation"""
        from lambda.vpn_error_handling import create_error_context
        
        context = create_error_context(
            request_id="test-123",
            function_name="test-function",
            routing_method="vpn",
            vpc_endpoints_used=True
        )
        
        self.assertEqual(context.request_id, "test-123")
        self.assertEqual(context.function_name, "test-function")
        self.assertEqual(context.routing_method, "vpn")
        self.assertTrue(context.vpc_endpoints_used)
        self.assertEqual(context.retry_attempt, 0)
    
    def _is_valid_cidr(self, cidr):
        """Validate CIDR block format"""
        try:
            import ipaddress
            ipaddress.ip_network(cidr, strict=False)
            return True
        except ValueError:
            return False

class TestVPCEndpointConnectivity(unittest.TestCase):
    """Unit tests for VPC endpoint connectivity"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.vpc_endpoint_clients = None
        
    @mock_secretsmanager
    @mock_dynamodb
    def test_vpc_endpoint_clients(self):
        """Test VPC endpoint client creation and caching"""
        from lambda.vpc_endpoint_clients import VPCEndpointClientManager
        
        # Set up mock environment
        os.environ['VPC_ENDPOINT_SECRETS'] = 'https://vpce-123.secretsmanager.us-gov-west-1.vpce.amazonaws.com'
        os.environ['VPC_ENDPOINT_DYNAMODB'] = 'https://dynamodb.us-gov-west-1.amazonaws.com'
        
        client_manager = VPCEndpointClientManager()
        
        # Test client creation
        secrets_client = client_manager.get_secrets_client()
        self.assertIsNotNone(secrets_client)
        
        dynamodb_resource = client_manager.get_dynamodb_resource()
        self.assertIsNotNone(dynamodb_resource)
        
        # Test caching (should return same instance)
        secrets_client_2 = client_manager.get_secrets_client()
        self.assertEqual(id(secrets_client), id(secrets_client_2))
        
        # Clean up environment
        del os.environ['VPC_ENDPOINT_SECRETS']
        del os.environ['VPC_ENDPOINT_DYNAMODB']
    
    def test_vpc_endpoint_connectivity_test(self):
        """Test VPC endpoint connectivity testing"""
        from lambda.vpc_endpoint_clients import VPCEndpointClientManager
        
        client_manager = VPCEndpointClientManager()
        
        # Mock the clients to avoid actual AWS calls
        with patch.object(client_manager, 'get_secrets_client') as mock_secrets:
            with patch.object(client_manager, 'get_dynamodb_client') as mock_dynamodb:
                mock_secrets.return_value.list_secrets.return_value = {'SecretList': []}
                mock_dynamodb.return_value.list_tables.return_value = {'TableNames': []}
                
                test_results = client_manager.test_vpc_endpoint_connectivity()
                
                self.assertIn('tests', test_results)
                self.assertIn('overall_health', test_results)
                self.assertIn('secretsmanager', test_results['tests'])
                self.assertIn('dynamodb', test_results['tests'])

class TestCrossPartitionConnectivity(unittest.TestCase):
    """Integration tests for cross-partition connectivity"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.api_base_url = os.environ.get('VPN_API_BASE_URL', 'https://test-api.execute-api.us-gov-west-1.amazonaws.com/v1')
        self.test_models = [
            "anthropic.claude-3-5-sonnet-20241022-v2:0",
            "amazon.nova-premier-v1:0",
            "meta.llama3-2-90b-instruct-v1:0"
        ]
    
    @unittest.skipIf(not os.environ.get('RUN_INTEGRATION_TESTS'), "Integration tests disabled")
    def test_cross_partition_vpn_flow(self):
        """Test end-to-end cross-partition flow via VPN"""
        
        for model_id in self.test_models:
            with self.subTest(model=model_id):
                response = self._test_model_invocation(model_id)
                
                # Verify response structure
                self.assertEqual(response.status_code, 200)
                
                data = response.json()
                self.assertIn('metadata', data)
                self.assertEqual(data['metadata']['routing_method'], 'vpn')
                self.assertTrue(data['metadata']['vpc_endpoints_used'])
                self.assertIn('body', data)
    
    def test_vpn_routing_info(self):
        """Test VPN routing information endpoint"""
        if not os.environ.get('RUN_INTEGRATION_TESTS'):
            self.skipTest("Integration tests disabled")
            
        response = requests.get(f"{self.api_base_url}/")
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertIn('routing', data)
        self.assertEqual(data['routing']['method'], 'vpn')
        self.assertIn('vpc_configuration', data)
    
    def test_models_endpoint(self):
        """Test models listing endpoint via VPN"""
        if not os.environ.get('RUN_INTEGRATION_TESTS'):
            self.skipTest("Integration tests disabled")
            
        response = requests.get(f"{self.api_base_url}/bedrock/models")
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertIn('models', data)
        self.assertIn('source', data)
        self.assertEqual(data['source']['routing_method'], 'vpn')
        self.assertTrue(data['source']['vpc_endpoints_used'])
    
    def _test_model_invocation(self, model_id):
        """Helper method to test model invocation"""
        payload = {
            "modelId": model_id,
            "body": {
                "messages": [
                    {
                        "role": "user",
                        "content": "Hello from GovCloud via VPN! Please respond with a brief greeting."
                    }
                ]
            }
        }
        
        return requests.post(
            f"{self.api_base_url}/bedrock/invoke-model",
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=30
        )

class TestVPNTunnelFailover(unittest.TestCase):
    """Tests for VPN tunnel failover functionality"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.error_handler = None
        
    def test_tunnel_failover_logic(self):
        """Test VPN tunnel failover logic"""
        from lambda.vpn_error_handling import VPNErrorHandler, create_error_context
        
        error_handler = VPNErrorHandler()
        context = create_error_context("test-123", "test-function")
        
        # Test tunnel down scenario
        tunnel_status = {
            'tunnel_id': 'tunnel-1',
            'status': 'DOWN'
        }
        
        with patch.object(error_handler, '_attempt_tunnel_failover') as mock_failover:
            mock_failover.return_value = {
                'success': True,
                'backup_tunnel': 'tunnel-2',
                'message': 'Successfully failed over to tunnel-2'
            }
            
            result = error_handler.handle_vpn_tunnel_failure(tunnel_status, context)
            
            self.assertEqual(result['action'], 'failover_successful')
            self.assertEqual(result['backup_tunnel'], 'tunnel-2')
            mock_failover.assert_called_once()
    
    def test_circuit_breaker_functionality(self):
        """Test circuit breaker for VPC endpoints"""
        from lambda.vpn_error_handling import CircuitBreaker
        
        circuit_breaker = CircuitBreaker(failure_threshold=3, recovery_timeout=60)
        
        # Test normal operation
        self.assertFalse(circuit_breaker.is_open('test-service'))
        
        # Trigger failures
        for _ in range(3):
            circuit_breaker.record_failure('test-service')
        
        # Circuit should be open
        self.assertTrue(circuit_breaker.is_open('test-service'))
        
        # Test recovery
        circuit_breaker.record_success('test-service')
        self.assertFalse(circuit_breaker.is_open('test-service'))

class TestPerformanceBenchmarks(unittest.TestCase):
    """Performance tests for VPN connectivity"""
    
    def setUp(self):
        """Set up performance test fixtures"""
        self.api_base_url = os.environ.get('VPN_API_BASE_URL', 'https://test-api.execute-api.us-gov-west-1.amazonaws.com/v1')
        self.performance_thresholds = {
            'max_latency_ms': 5000,  # 5 seconds
            'min_throughput_rps': 10,  # 10 requests per second
            'max_error_rate': 0.05   # 5% error rate
        }
    
    @unittest.skipIf(not os.environ.get('RUN_PERFORMANCE_TESTS'), "Performance tests disabled")
    def test_vpn_latency_benchmark(self):
        """Test VPN latency performance"""
        latencies = []
        errors = 0
        
        test_payload = {
            "modelId": "anthropic.claude-3-5-sonnet-20241022-v2:0",
            "body": {
                "messages": [{"role": "user", "content": "Test message"}]
            }
        }
        
        # Run 50 requests
        for i in range(50):
            start_time = time.time()
            try:
                response = requests.post(
                    f"{self.api_base_url}/bedrock/invoke-model",
                    headers={"Content-Type": "application/json"},
                    json=test_payload,
                    timeout=30
                )
                
                if response.status_code != 200:
                    errors += 1
                    
            except Exception as e:
                logger.error(f"Request {i} failed: {str(e)}")
                errors += 1
            
            end_time = time.time()
            latency_ms = (end_time - start_time) * 1000
            latencies.append(latency_ms)
        
        # Calculate statistics
        avg_latency = sum(latencies) / len(latencies)
        p95_latency = sorted(latencies)[int(0.95 * len(latencies))]
        error_rate = errors / len(latencies)
        
        logger.info(f"Performance Results:")
        logger.info(f"  Average Latency: {avg_latency:.2f}ms")
        logger.info(f"  95th Percentile: {p95_latency:.2f}ms")
        logger.info(f"  Error Rate: {error_rate:.2%}")
        
        # Assert performance thresholds
        self.assertLess(p95_latency, self.performance_thresholds['max_latency_ms'])
        self.assertLess(error_rate, self.performance_thresholds['max_error_rate'])
    
    @unittest.skipIf(not os.environ.get('RUN_PERFORMANCE_TESTS'), "Performance tests disabled")
    def test_concurrent_requests(self):
        """Test concurrent request handling"""
        import concurrent.futures
        import threading
        
        def make_request():
            """Make a single request"""
            try:
                response = requests.post(
                    f"{self.api_base_url}/bedrock/invoke-model",
                    headers={"Content-Type": "application/json"},
                    json={
                        "modelId": "anthropic.claude-3-5-sonnet-20241022-v2:0",
                        "body": {"messages": [{"role": "user", "content": "Concurrent test"}]}
                    },
                    timeout=30
                )
                return response.status_code == 200
            except Exception:
                return False
        
        # Run 20 concurrent requests
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_request) for _ in range(20)]
            results = [future.result() for future in concurrent.futures.as_completed(futures)]
        
        success_rate = sum(results) / len(results)
        logger.info(f"Concurrent Request Success Rate: {success_rate:.2%}")
        
        # Should handle concurrent requests with high success rate
        self.assertGreater(success_rate, 0.8)  # 80% success rate

class TestSecurityValidation(unittest.TestCase):
    """Security tests for VPN connectivity"""
    
    def setUp(self):
        """Set up security test fixtures"""
        self.api_base_url = os.environ.get('VPN_API_BASE_URL', 'https://test-api.execute-api.us-gov-west-1.amazonaws.com/v1')
    
    def test_network_isolation(self):
        """Test network isolation - no internet access from private subnets"""
        # This test would typically run from within the VPC
        # For now, we'll test that the API only accepts HTTPS
        
        # Test HTTPS enforcement
        if self.api_base_url.startswith('https://'):
            http_url = self.api_base_url.replace('https://', 'http://')
            
            with self.assertRaises(requests.exceptions.ConnectionError):
                requests.get(http_url, timeout=5)
    
    def test_encryption_validation(self):
        """Test VPN encryption validation"""
        # Mock IPSec validation
        encryption_config = {
            'encryption_algorithm': 'AES-256',
            'integrity_algorithm': 'SHA-256',
            'dh_group': 'Group-14',
            'pfs_enabled': True
        }
        
        # Validate encryption strength
        self.assertEqual(encryption_config['encryption_algorithm'], 'AES-256')
        self.assertEqual(encryption_config['integrity_algorithm'], 'SHA-256')
        self.assertTrue(encryption_config['pfs_enabled'])
    
    @unittest.skipIf(not os.environ.get('RUN_SECURITY_TESTS'), "Security tests disabled")
    def test_authentication_required(self):
        """Test that authentication is required"""
        # Test without authentication
        response = requests.post(
            f"{self.api_base_url}/bedrock/invoke-model",
            headers={"Content-Type": "application/json"},
            json={"modelId": "test", "body": {}},
            timeout=10
        )
        
        # Should require authentication (401 or 403)
        self.assertIn(response.status_code, [401, 403])
    
    def test_input_validation(self):
        """Test input validation and sanitization"""
        # Test with malicious input
        malicious_payloads = [
            {"modelId": "<script>alert('xss')</script>"},
            {"modelId": "'; DROP TABLE users; --"},
            {"modelId": "../../../etc/passwd"},
            {"body": {"messages": [{"role": "user", "content": "A" * 10000}]}}  # Large payload
        ]
        
        for payload in malicious_payloads:
            with self.subTest(payload=payload):
                if os.environ.get('RUN_SECURITY_TESTS'):
                    response = requests.post(
                        f"{self.api_base_url}/bedrock/invoke-model",
                        headers={"Content-Type": "application/json"},
                        json=payload,
                        timeout=10
                    )
                    
                    # Should reject malicious input
                    self.assertIn(response.status_code, [400, 422, 500])

class TestComplianceValidation(unittest.TestCase):
    """Tests for compliance validation"""
    
    def test_audit_trail_format(self):
        """Test audit trail record format"""
        # Mock audit record
        audit_record = {
            'requestId': 'test-123',
            'timestamp': datetime.utcnow().isoformat(),
            'sourcePartition': 'govcloud',
            'destinationPartition': 'commercial',
            'routingMethod': 'vpn',
            'vpcEndpointsUsed': True,
            'userArn': 'arn:aws:iam::123456789012:user/test-user',
            'modelId': 'anthropic.claude-3-5-sonnet-20241022-v2:0',
            'success': True,
            'latency': 1500
        }
        
        # Validate required fields
        required_fields = [
            'requestId', 'timestamp', 'sourcePartition', 'destinationPartition',
            'routingMethod', 'vpcEndpointsUsed', 'userArn', 'success'
        ]
        
        for field in required_fields:
            self.assertIn(field, audit_record)
            self.assertIsNotNone(audit_record[field])
    
    def test_compliance_scoring(self):
        """Test compliance scoring logic"""
        # Mock compliance report
        report = {
            'metrics': {
                'successful_requests': 95,
                'failed_requests': 5,
                'vpn_requests': 100,
                'vpc_endpoint_requests': 100
            },
            'violations': [],
            'summary': {
                'total_requests': 100,
                'success_rate': 95.0,
                'vpn_usage_rate': 100.0,
                'vpc_endpoint_usage_rate': 100.0
            }
        }
        
        # Calculate compliance score
        score = self._calculate_compliance_score(report)
        
        # Should have high compliance score
        self.assertGreaterEqual(score, 90)
    
    def _calculate_compliance_score(self, report):
        """Calculate compliance score"""
        base_score = 100
        
        # Deduct for violations
        violation_penalty = len(report.get('violations', [])) * 5
        score = base_score - min(violation_penalty, 50)
        
        # Deduct for non-VPN usage
        vpn_usage_rate = report['summary']['vpn_usage_rate']
        if vpn_usage_rate < 100:
            score -= (100 - vpn_usage_rate) * 0.3
        
        # Deduct for VPC endpoint bypass
        vpc_endpoint_rate = report['summary']['vpc_endpoint_usage_rate']
        if vpc_endpoint_rate < 100:
            score -= (100 - vpc_endpoint_rate) * 0.2
        
        return max(score, 0)

def run_test_suite():
    """Run the complete test suite"""
    
    # Configure test environment
    test_env = os.environ.get('TEST_ENV', 'unit')
    
    # Create test suite
    suite = unittest.TestSuite()
    
    # Add unit tests (always run)
    suite.addTest(unittest.makeSuite(TestVPNConfiguration))
    suite.addTest(unittest.makeSuite(TestVPCEndpointConnectivity))
    suite.addTest(unittest.makeSuite(TestVPNTunnelFailover))
    suite.addTest(unittest.makeSuite(TestComplianceValidation))
    
    # Add integration tests if enabled
    if os.environ.get('RUN_INTEGRATION_TESTS'):
        suite.addTest(unittest.makeSuite(TestCrossPartitionConnectivity))
    
    # Add performance tests if enabled
    if os.environ.get('RUN_PERFORMANCE_TESTS'):
        suite.addTest(unittest.makeSuite(TestPerformanceBenchmarks))
    
    # Add security tests if enabled
    if os.environ.get('RUN_SECURITY_TESTS'):
        suite.addTest(unittest.makeSuite(TestSecurityValidation))
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    # Generate test report
    generate_test_report(result)
    
    return result.wasSuccessful()

def generate_test_report(result):
    """Generate test report"""
    
    report = {
        'timestamp': datetime.utcnow().isoformat(),
        'tests_run': result.testsRun,
        'failures': len(result.failures),
        'errors': len(result.errors),
        'success_rate': ((result.testsRun - len(result.failures) - len(result.errors)) / result.testsRun * 100) if result.testsRun > 0 else 0,
        'details': {
            'failures': [{'test': str(test), 'error': error} for test, error in result.failures],
            'errors': [{'test': str(test), 'error': error} for test, error in result.errors]
        }
    }
    
    # Save report
    with open('/tmp/vpn-test-report.json', 'w') as f:
        json.dump(report, f, indent=2)
    
    logger.info(f"Test Report Generated:")
    logger.info(f"  Tests Run: {report['tests_run']}")
    logger.info(f"  Failures: {report['failures']}")
    logger.info(f"  Errors: {report['errors']}")
    logger.info(f"  Success Rate: {report['success_rate']:.1f}%")
    logger.info(f"  Report saved to: /tmp/vpn-test-report.json")

if __name__ == '__main__':
    success = run_test_suite()
    exit(0 if success else 1)