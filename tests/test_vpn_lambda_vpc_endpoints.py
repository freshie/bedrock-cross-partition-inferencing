"""
Unit tests for VPN Lambda VPC endpoint functionality
Tests VPC endpoint health checks, connectivity, and error handling
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
import json
import os
import sys
import socket
from datetime import datetime

# Add lambda directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lambda'))

from dual_routing_vpn_lambda import VPCEndpointClients

class TestVPCEndpointClients(unittest.TestCase):
    """Test cases for VPC endpoint client functionality"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Reset singleton instance for each test
        VPCEndpointClients._instance = None
        VPCEndpointClients._clients = {}
        VPCEndpointClients._health_status = {}
        
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'VPC_ENDPOINT_SECRETS': 'https://vpce-secrets.us-gov-west-1.vpce.amazonaws.com',
            'VPC_ENDPOINT_DYNAMODB': 'https://vpce-dynamodb.us-gov-west-1.vpce.amazonaws.com',
            'VPC_ENDPOINT_LOGS': 'https://vpce-logs.us-gov-west-1.vpce.amazonaws.com',
            'VPC_ENDPOINT_MONITORING': 'https://vpce-monitoring.us-gov-west-1.vpce.amazonaws.com',
            'COMMERCIAL_BEDROCK_ENDPOINT': 'https://bedrock-runtime.us-east-1.amazonaws.com'
        })
        self.env_patcher.start()
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
        # Reset singleton for next test
        VPCEndpointClients._instance = None
    
    def test_singleton_pattern(self):
        """Test that VPCEndpointClients follows singleton pattern"""
        client1 = VPCEndpointClients()
        client2 = VPCEndpointClients()
        
        self.assertIs(client1, client2)
        self.assertEqual(id(client1), id(client2))
    
    @patch('dual_routing_vpn_lambda.boto3.client')
    def test_get_secrets_client_with_vpc_endpoint(self, mock_boto_client):
        """Test secrets client creation with VPC endpoint"""
        mock_client = Mock()
        mock_boto_client.return_value = mock_client
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.get_secrets_client()
        
        mock_boto_client.assert_called_with(
            'secretsmanager', 
            endpoint_url='https://vpce-secrets.us-gov-west-1.vpce.amazonaws.com'
        )
        self.assertEqual(result, mock_client)
    
    @patch.dict(os.environ, {'VPC_ENDPOINT_SECRETS': ''})
    @patch('dual_routing_vpn_lambda.boto3.client')
    def test_get_secrets_client_without_vpc_endpoint(self, mock_boto_client):
        """Test secrets client creation without VPC endpoint"""
        mock_client = Mock()
        mock_boto_client.return_value = mock_client
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.get_secrets_client()
        
        mock_boto_client.assert_called_with('secretsmanager')
        self.assertEqual(result, mock_client)
    
    @patch('dual_routing_vpn_lambda.boto3.resource')
    def test_get_dynamodb_resource_with_vpc_endpoint(self, mock_boto_resource):
        """Test DynamoDB resource creation with VPC endpoint"""
        mock_resource = Mock()
        mock_boto_resource.return_value = mock_resource
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.get_dynamodb_resource()
        
        mock_boto_resource.assert_called_with(
            'dynamodb', 
            endpoint_url='https://vpce-dynamodb.us-gov-west-1.vpce.amazonaws.com'
        )
        self.assertEqual(result, mock_resource)
    
    @patch('dual_routing_vpn_lambda.boto3.client')
    def test_get_cloudwatch_client_with_vpc_endpoint(self, mock_boto_client):
        """Test CloudWatch client creation with VPC endpoint"""
        mock_client = Mock()
        mock_boto_client.return_value = mock_client
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.get_cloudwatch_client()
        
        mock_boto_client.assert_called_with(
            'cloudwatch', 
            endpoint_url='https://vpce-monitoring.us-gov-west-1.vpce.amazonaws.com'
        )
        self.assertEqual(result, mock_client)
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_check_vpc_endpoint_health_success(self, mock_socket):
        """Test successful VPC endpoint health check"""
        # Mock successful socket connection
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 0  # Success
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.check_vpc_endpoint_health(
            'test-endpoint',
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com'
        )
        
        self.assertTrue(result)
        self.assertIn('test-endpoint', vpc_clients._health_status)
        self.assertTrue(vpc_clients._health_status['test-endpoint']['healthy'])
        self.assertIn('last_check', vpc_clients._health_status['test-endpoint'])
        self.assertIn('endpoint_url', vpc_clients._health_status['test-endpoint'])
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_check_vpc_endpoint_health_failure(self, mock_socket):
        """Test failed VPC endpoint health check"""
        # Mock failed socket connection
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 1  # Connection refused
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.check_vpc_endpoint_health(
            'test-endpoint',
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com'
        )
        
        self.assertFalse(result)
        self.assertIn('test-endpoint', vpc_clients._health_status)
        self.assertFalse(vpc_clients._health_status['test-endpoint']['healthy'])
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_check_vpc_endpoint_health_exception(self, mock_socket):
        """Test VPC endpoint health check with exception"""
        # Mock socket exception
        mock_socket.side_effect = Exception('Network error')
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.check_vpc_endpoint_health(
            'test-endpoint',
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com'
        )
        
        self.assertFalse(result)
        self.assertIn('test-endpoint', vpc_clients._health_status)
        self.assertFalse(vpc_clients._health_status['test-endpoint']['healthy'])
        self.assertIn('error', vpc_clients._health_status['test-endpoint'])
    
    def test_check_vpc_endpoint_health_no_endpoint(self):
        """Test VPC endpoint health check with no endpoint URL"""
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.check_vpc_endpoint_health('test-endpoint', '')
        
        self.assertTrue(result)  # Should return True for default endpoints
        self.assertIn('test-endpoint', vpc_clients._health_status)
        self.assertTrue(vpc_clients._health_status['test-endpoint']['healthy'])
        self.assertEqual(vpc_clients._health_status['test-endpoint']['endpoint_url'], 'default')
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_validate_vpn_connectivity_success(self, mock_socket):
        """Test successful VPN connectivity validation"""
        # Mock successful socket connection
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 0  # Success
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        
        # Should not raise exception
        vpc_clients.validate_vpn_connectivity()
        
        # Check health status was updated
        self.assertIn('vpn_tunnel', vpc_clients._health_status)
        self.assertTrue(vpc_clients._health_status['vpn_tunnel']['healthy'])
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_validate_vpn_connectivity_failure(self, mock_socket):
        """Test failed VPN connectivity validation"""
        # Mock failed socket connection
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 1  # Connection refused
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        
        with self.assertRaises(Exception) as context:
            vpc_clients.validate_vpn_connectivity()
        
        self.assertIn('VPN tunnel validation failed', str(context.exception))
        self.assertIn('vpn_tunnel', vpc_clients._health_status)
        self.assertFalse(vpc_clients._health_status['vpn_tunnel']['healthy'])
    
    @patch.dict(os.environ, {'COMMERCIAL_BEDROCK_ENDPOINT': ''})
    def test_validate_vpn_connectivity_no_endpoint(self):
        """Test VPN connectivity validation with no endpoint configured"""
        vpc_clients = VPCEndpointClients()
        
        # Should not raise exception and return True
        result = vpc_clients.validate_vpn_connectivity()
        self.assertTrue(result)
    
    def test_get_health_status(self):
        """Test getting health status of all endpoints"""
        vpc_clients = VPCEndpointClients()
        
        # Set some test health status
        vpc_clients._health_status = {
            'secrets': {'healthy': True, 'last_check': '2023-01-01T00:00:00Z'},
            'dynamodb': {'healthy': False, 'error': 'Connection timeout'},
            'vpn_tunnel': {'healthy': True, 'endpoint': 'test-endpoint'}
        }
        
        result = vpc_clients.get_health_status()
        
        # Should return a copy of the health status
        self.assertEqual(len(result), 3)
        self.assertTrue(result['secrets']['healthy'])
        self.assertFalse(result['dynamodb']['healthy'])
        self.assertTrue(result['vpn_tunnel']['healthy'])
        
        # Verify it's a copy, not the original
        self.assertIsNot(result, vpc_clients._health_status)
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_health_check_with_custom_port(self, mock_socket):
        """Test health check with custom port in URL"""
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 0
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        result = vpc_clients.check_vpc_endpoint_health(
            'custom-port-endpoint',
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com:8443'
        )
        
        self.assertTrue(result)
        # Verify socket was called with custom port
        mock_sock.connect_ex.assert_called_with(('vpce-test.us-gov-west-1.vpce.amazonaws.com', 8443))
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_health_check_timeout_handling(self, mock_socket):
        """Test health check with socket timeout"""
        mock_sock = Mock()
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        vpc_clients.check_vpc_endpoint_health(
            'timeout-test',
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com'
        )
        
        # Verify timeout was set
        mock_sock.settimeout.assert_called_with(2)
        mock_sock.close.assert_called_once()
    
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_multiple_health_checks(self, mock_socket):
        """Test multiple health checks update status correctly"""
        mock_sock = Mock()
        mock_socket.return_value = mock_sock
        
        vpc_clients = VPCEndpointClients()
        
        # First check - success
        mock_sock.connect_ex.return_value = 0
        result1 = vpc_clients.check_vpc_endpoint_health(
            'multi-test',
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com'
        )
        
        # Second check - failure
        mock_sock.connect_ex.return_value = 1
        result2 = vpc_clients.check_vpc_endpoint_health(
            'multi-test',
            'https://vpce-test.us-gov-west-1.vpce.amazonaws.com'
        )
        
        self.assertTrue(result1)
        self.assertFalse(result2)
        
        # Status should reflect the latest check
        self.assertFalse(vpc_clients._health_status['multi-test']['healthy'])

class TestVPCEndpointIntegration(unittest.TestCase):
    """Integration tests for VPC endpoint functionality"""
    
    def setUp(self):
        """Set up integration test fixtures"""
        # Reset singleton
        VPCEndpointClients._instance = None
        
        self.env_patcher = patch.dict(os.environ, {
            'VPC_ENDPOINT_SECRETS': 'https://vpce-secrets.us-gov-west-1.vpce.amazonaws.com',
            'VPC_ENDPOINT_DYNAMODB': 'https://vpce-dynamodb.us-gov-west-1.vpce.amazonaws.com'
        })
        self.env_patcher.start()
    
    def tearDown(self):
        """Clean up integration test fixtures"""
        self.env_patcher.stop()
        VPCEndpointClients._instance = None
    
    @patch('dual_routing_vpn_lambda.boto3.client')
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_secrets_client_with_health_check(self, mock_socket, mock_boto_client):
        """Test secrets client creation with health check integration"""
        # Mock successful health check
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 0
        mock_socket.return_value = mock_sock
        
        # Mock boto3 client
        mock_client = Mock()
        mock_boto_client.return_value = mock_client
        
        vpc_clients = VPCEndpointClients()
        
        # Get secrets client (should trigger health check)
        result = vpc_clients.get_secrets_client()
        
        # Verify client was created with VPC endpoint
        mock_boto_client.assert_called_with(
            'secretsmanager',
            endpoint_url='https://vpce-secrets.us-gov-west-1.vpce.amazonaws.com'
        )
        
        # Verify health status was updated
        health_status = vpc_clients.get_health_status()
        self.assertTrue(health_status['secrets']['healthy'])
    
    @patch('dual_routing_vpn_lambda.boto3.client')
    @patch('dual_routing_vpn_lambda.socket.socket')
    def test_secrets_client_with_failed_health_check(self, mock_socket, mock_boto_client):
        """Test secrets client fallback when health check fails"""
        # Mock failed health check
        mock_sock = Mock()
        mock_sock.connect_ex.return_value = 1  # Connection failed
        mock_socket.return_value = mock_sock
        
        # Mock boto3 client
        mock_client = Mock()
        mock_boto_client.return_value = mock_client
        
        vpc_clients = VPCEndpointClients()
        
        # Get secrets client (should fallback to default)
        result = vpc_clients.get_secrets_client()
        
        # Should fallback to default client (no endpoint_url)
        mock_boto_client.assert_called_with('secretsmanager')
        
        # Verify health status shows failure
        health_status = vpc_clients.get_health_status()
        self.assertFalse(health_status['secrets']['healthy'])

if __name__ == '__main__':
    unittest.main(verbosity=2)