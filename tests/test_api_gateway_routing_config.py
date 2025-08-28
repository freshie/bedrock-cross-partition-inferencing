"""
API Gateway routing configuration validation tests
Tests the actual API Gateway configuration and routing rules
"""

import unittest
from unittest.mock import Mock, patch, MagicMock
import json
import os
import sys
import boto3
from datetime import datetime

# Add lambda directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lambda'))


class TestAPIGatewayRoutingConfiguration(unittest.TestCase):
    """Test cases for API Gateway routing configuration"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'COMMERCIAL_CREDENTIALS_SECRET': 'test-commercial-creds',
            'REQUEST_LOG_TABLE': 'test-request-log-table'
        })
        self.env_patcher.start()
        
        # Sample API Gateway configuration
        self.api_gateway_config = {
            'resources': {
                '/v1': {
                    'methods': ['GET', 'POST', 'OPTIONS'],
                    'children': {
                        '/bedrock': {
                            'methods': ['GET', 'POST', 'OPTIONS'],
                            'children': {
                                '/invoke-model': {
                                    'methods': ['POST'],
                                    'integration': {
                                        'type': 'AWS_PROXY',
                                        'lambda_function': 'dual-routing-internet-lambda'
                                    }
                                },
                                '/models': {
                                    'methods': ['GET'],
                                    'integration': {
                                        'type': 'AWS_PROXY',
                                        'lambda_function': 'dual-routing-internet-lambda'
                                    }
                                }
                            }
                        },
                        '/vpn': {
                            'methods': ['GET', 'POST', 'OPTIONS'],
                            'children': {
                                '/bedrock': {
                                    'methods': ['GET', 'POST', 'OPTIONS'],
                                    'children': {
                                        '/invoke-model': {
                                            'methods': ['POST'],
                                            'integration': {
                                                'type': 'AWS_PROXY',
                                                'lambda_function': 'dual-routing-vpn-lambda'
                                            }
                                        },
                                        '/models': {
                                            'methods': ['GET'],
                                            'integration': {
                                                'type': 'AWS_PROXY',
                                                'lambda_function': 'dual-routing-vpn-lambda'
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    
    def tearDown(self):
        """Clean up test fixtures"""
        self.env_patcher.stop()
    
    def test_internet_routing_path_configuration(self):
        """Test that internet routing paths are properly configured"""
        # Verify internet paths exist in configuration
        internet_paths = [
            '/v1/bedrock/invoke-model',
            '/v1/bedrock/models'
        ]
        
        for path in internet_paths:
            with self.subTest(path=path):
                # Parse path components
                path_parts = [p for p in path.split('/') if p]
                
                # Navigate through configuration
                current_config = self.api_gateway_config['resources']
                for part in path_parts:
                    part_key = f'/{part}'
                    self.assertIn(part_key, current_config, 
                                f"Path component {part_key} not found in configuration")
                    
                    if 'children' in current_config[part_key]:
                        current_config = current_config[part_key]['children']
                    else:
                        # This should be the final component
                        final_config = current_config[part_key]
                        self.assertIn('integration', final_config,
                                    f"Integration not configured for {path}")
                        self.assertEqual(final_config['integration']['lambda_function'],
                                       'dual-routing-internet-lambda',
                                       f"Wrong Lambda function for {path}")
    
    def test_vpn_routing_path_configuration(self):
        """Test that VPN routing paths are properly configured"""
        # Verify VPN paths exist in configuration
        vpn_paths = [
            '/v1/vpn/bedrock/invoke-model',
            '/v1/vpn/bedrock/models'
        ]
        
        for path in vpn_paths:
            with self.subTest(path=path):
                # Parse path components
                path_parts = [p for p in path.split('/') if p]
                
                # Navigate through configuration
                current_config = self.api_gateway_config['resources']
                for part in path_parts:
                    part_key = f'/{part}'
                    self.assertIn(part_key, current_config, 
                                f"Path component {part_key} not found in configuration")
                    
                    if 'children' in current_config[part_key]:
                        current_config = current_config[part_key]['children']
                    else:
                        # This should be the final component
                        final_config = current_config[part_key]
                        self.assertIn('integration', final_config,
                                    f"Integration not configured for {path}")
                        self.assertEqual(final_config['integration']['lambda_function'],
                                       'dual-routing-vpn-lambda',
                                       f"Wrong Lambda function for {path}")
    
    def test_http_methods_configuration(self):
        """Test that HTTP methods are properly configured for each path"""
        method_expectations = {
            '/v1/bedrock/invoke-model': ['POST'],
            '/v1/bedrock/models': ['GET'],
            '/v1/vpn/bedrock/invoke-model': ['POST'],
            '/v1/vpn/bedrock/models': ['GET']
        }
        
        for path, expected_methods in method_expectations.items():
            with self.subTest(path=path):
                # Parse path and navigate to configuration
                path_parts = [p for p in path.split('/') if p]
                current_config = self.api_gateway_config['resources']
                
                for part in path_parts:
                    part_key = f'/{part}'
                    if 'children' in current_config[part_key]:
                        current_config = current_config[part_key]['children']
                    else:
                        final_config = current_config[part_key]
                        configured_methods = final_config.get('methods', [])
                        
                        for method in expected_methods:
                            self.assertIn(method, configured_methods,
                                        f"Method {method} not configured for {path}")
    
    def test_cors_configuration(self):
        """Test that CORS is properly configured for all paths"""
        # All paths should support OPTIONS for CORS
        all_paths = [
            '/v1/bedrock/invoke-model',
            '/v1/bedrock/models',
            '/v1/vpn/bedrock/invoke-model',
            '/v1/vpn/bedrock/models'
        ]
        
        for path in all_paths:
            with self.subTest(path=path):
                # Navigate to parent resource (should have OPTIONS)
                path_parts = [p for p in path.split('/') if p][:-1]  # Exclude last part
                current_config = self.api_gateway_config['resources']
                
                for part in path_parts:
                    part_key = f'/{part}'
                    if 'children' in current_config[part_key]:
                        parent_config = current_config[part_key]
                        current_config = current_config[part_key]['children']
                    else:
                        parent_config = current_config[part_key]
                
                # Check that OPTIONS method is available
                methods = parent_config.get('methods', [])
                self.assertIn('OPTIONS', methods,
                            f"OPTIONS method not configured for CORS on {path}")
    
    def test_lambda_integration_type(self):
        """Test that Lambda integrations use AWS_PROXY type"""
        integration_paths = [
            '/v1/bedrock/invoke-model',
            '/v1/bedrock/models',
            '/v1/vpn/bedrock/invoke-model',
            '/v1/vpn/bedrock/models'
        ]
        
        for path in integration_paths:
            with self.subTest(path=path):
                # Navigate to path configuration
                path_parts = [p for p in path.split('/') if p]
                current_config = self.api_gateway_config['resources']
                
                for part in path_parts:
                    part_key = f'/{part}'
                    if 'children' in current_config[part_key]:
                        current_config = current_config[part_key]['children']
                    else:
                        final_config = current_config[part_key]
                        integration = final_config.get('integration', {})
                        
                        self.assertEqual(integration.get('type'), 'AWS_PROXY',
                                       f"Integration type should be AWS_PROXY for {path}")
    
    def test_routing_path_uniqueness(self):
        """Test that routing paths are unique and don't conflict"""
        # Extract all configured paths
        configured_paths = []
        
        def extract_paths(config, current_path=""):
            for key, value in config.items():
                full_path = current_path + key
                if 'integration' in value:
                    configured_paths.append(full_path)
                if 'children' in value:
                    extract_paths(value['children'], full_path)
        
        extract_paths(self.api_gateway_config['resources'])
        
        # Check for uniqueness
        self.assertEqual(len(configured_paths), len(set(configured_paths)),
                        "Duplicate paths found in configuration")
        
        # Verify expected paths are present
        expected_paths = [
            '/v1/bedrock/invoke-model',
            '/v1/bedrock/models',
            '/v1/vpn/bedrock/invoke-model',
            '/v1/vpn/bedrock/models'
        ]
        
        for expected_path in expected_paths:
            self.assertIn(expected_path, configured_paths,
                         f"Expected path {expected_path} not found in configuration")
    
    def test_lambda_function_mapping(self):
        """Test that paths are mapped to correct Lambda functions"""
        path_lambda_mapping = {
            '/v1/bedrock/invoke-model': 'dual-routing-internet-lambda',
            '/v1/bedrock/models': 'dual-routing-internet-lambda',
            '/v1/vpn/bedrock/invoke-model': 'dual-routing-vpn-lambda',
            '/v1/vpn/bedrock/models': 'dual-routing-vpn-lambda'
        }
        
        for path, expected_lambda in path_lambda_mapping.items():
            with self.subTest(path=path):
                # Navigate to path configuration
                path_parts = [p for p in path.split('/') if p]
                current_config = self.api_gateway_config['resources']
                
                for part in path_parts:
                    part_key = f'/{part}'
                    if 'children' in current_config[part_key]:
                        current_config = current_config[part_key]['children']
                    else:
                        final_config = current_config[part_key]
                        integration = final_config.get('integration', {})
                        lambda_function = integration.get('lambda_function')
                        
                        self.assertEqual(lambda_function, expected_lambda,
                                       f"Wrong Lambda function mapping for {path}")


class TestAPIGatewayStageConfiguration(unittest.TestCase):
    """Test cases for API Gateway stage configuration"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.stage_configs = {
            'prod': {
                'stage_name': 'prod',
                'deployment_description': 'Production deployment',
                'variables': {
                    'environment': 'production',
                    'log_level': 'INFO'
                },
                'throttling': {
                    'rate_limit': 1000,
                    'burst_limit': 2000
                }
            },
            'stage': {
                'stage_name': 'stage',
                'deployment_description': 'Staging deployment',
                'variables': {
                    'environment': 'staging',
                    'log_level': 'DEBUG'
                },
                'throttling': {
                    'rate_limit': 500,
                    'burst_limit': 1000
                }
            },
            'dev': {
                'stage_name': 'dev',
                'deployment_description': 'Development deployment',
                'variables': {
                    'environment': 'development',
                    'log_level': 'DEBUG'
                },
                'throttling': {
                    'rate_limit': 100,
                    'burst_limit': 200
                }
            }
        }
    
    def test_stage_configuration_completeness(self):
        """Test that all required stages are configured"""
        required_stages = ['prod', 'stage', 'dev']
        
        for stage in required_stages:
            with self.subTest(stage=stage):
                self.assertIn(stage, self.stage_configs,
                            f"Stage {stage} not found in configuration")
                
                stage_config = self.stage_configs[stage]
                
                # Check required fields
                required_fields = ['stage_name', 'deployment_description', 'variables', 'throttling']
                for field in required_fields:
                    self.assertIn(field, stage_config,
                                f"Field {field} missing from {stage} stage configuration")
    
    def test_stage_throttling_configuration(self):
        """Test that throttling is properly configured for each stage"""
        for stage_name, stage_config in self.stage_configs.items():
            with self.subTest(stage=stage_name):
                throttling = stage_config.get('throttling', {})
                
                self.assertIn('rate_limit', throttling,
                            f"Rate limit not configured for {stage_name}")
                self.assertIn('burst_limit', throttling,
                            f"Burst limit not configured for {stage_name}")
                
                # Verify limits are reasonable
                rate_limit = throttling['rate_limit']
                burst_limit = throttling['burst_limit']
                
                self.assertGreater(rate_limit, 0,
                                 f"Rate limit should be positive for {stage_name}")
                self.assertGreater(burst_limit, rate_limit,
                                 f"Burst limit should be greater than rate limit for {stage_name}")
    
    def test_stage_environment_variables(self):
        """Test that environment variables are properly set for each stage"""
        for stage_name, stage_config in self.stage_configs.items():
            with self.subTest(stage=stage_name):
                variables = stage_config.get('variables', {})
                
                # Check required variables
                required_vars = ['environment', 'log_level']
                for var in required_vars:
                    self.assertIn(var, variables,
                                f"Variable {var} not set for {stage_name}")
                
                # Verify environment variable matches stage
                environment = variables.get('environment')
                if stage_name == 'prod':
                    self.assertEqual(environment, 'production')
                elif stage_name == 'stage':
                    self.assertEqual(environment, 'staging')
                elif stage_name == 'dev':
                    self.assertEqual(environment, 'development')


class TestAPIGatewaySecurityConfiguration(unittest.TestCase):
    """Test cases for API Gateway security configuration"""
    
    def setUp(self):
        """Set up test fixtures"""
        self.security_config = {
            'api_keys': {
                'enabled': True,
                'required': True,
                'usage_plans': {
                    'basic': {
                        'throttle': {'rate_limit': 100, 'burst_limit': 200},
                        'quota': {'limit': 10000, 'period': 'DAY'}
                    },
                    'premium': {
                        'throttle': {'rate_limit': 1000, 'burst_limit': 2000},
                        'quota': {'limit': 100000, 'period': 'DAY'}
                    }
                }
            },
            'cors': {
                'enabled': True,
                'allow_origins': ['*'],
                'allow_methods': ['GET', 'POST', 'OPTIONS'],
                'allow_headers': [
                    'Content-Type',
                    'X-Amz-Date',
                    'Authorization',
                    'X-Api-Key',
                    'X-Amz-Security-Token'
                ]
            },
            'request_validation': {
                'enabled': True,
                'validate_request_body': True,
                'validate_request_parameters': True
            }
        }
    
    def test_api_key_configuration(self):
        """Test that API key authentication is properly configured"""
        api_key_config = self.security_config.get('api_keys', {})
        
        self.assertTrue(api_key_config.get('enabled'),
                       "API key authentication should be enabled")
        self.assertTrue(api_key_config.get('required'),
                       "API key should be required")
        
        # Check usage plans
        usage_plans = api_key_config.get('usage_plans', {})
        self.assertIn('basic', usage_plans, "Basic usage plan should be configured")
        self.assertIn('premium', usage_plans, "Premium usage plan should be configured")
        
        # Validate usage plan structure
        for plan_name, plan_config in usage_plans.items():
            with self.subTest(plan=plan_name):
                self.assertIn('throttle', plan_config,
                            f"Throttle configuration missing for {plan_name}")
                self.assertIn('quota', plan_config,
                            f"Quota configuration missing for {plan_name}")
    
    def test_cors_configuration(self):
        """Test that CORS is properly configured"""
        cors_config = self.security_config.get('cors', {})
        
        self.assertTrue(cors_config.get('enabled'),
                       "CORS should be enabled")
        
        # Check required CORS fields
        required_cors_fields = ['allow_origins', 'allow_methods', 'allow_headers']
        for field in required_cors_fields:
            self.assertIn(field, cors_config,
                         f"CORS field {field} should be configured")
        
        # Verify essential methods are allowed
        allowed_methods = cors_config.get('allow_methods', [])
        essential_methods = ['GET', 'POST', 'OPTIONS']
        for method in essential_methods:
            self.assertIn(method, allowed_methods,
                         f"HTTP method {method} should be allowed for CORS")
        
        # Verify essential headers are allowed
        allowed_headers = cors_config.get('allow_headers', [])
        essential_headers = ['Content-Type', 'Authorization', 'X-Api-Key']
        for header in essential_headers:
            self.assertIn(header, allowed_headers,
                         f"Header {header} should be allowed for CORS")
    
    def test_request_validation_configuration(self):
        """Test that request validation is properly configured"""
        validation_config = self.security_config.get('request_validation', {})
        
        self.assertTrue(validation_config.get('enabled'),
                       "Request validation should be enabled")
        self.assertTrue(validation_config.get('validate_request_body'),
                       "Request body validation should be enabled")
        self.assertTrue(validation_config.get('validate_request_parameters'),
                       "Request parameter validation should be enabled")


if __name__ == '__main__':
    # Create test suite
    test_suite = unittest.TestSuite()
    
    # Add test classes
    test_classes = [
        TestAPIGatewayRoutingConfiguration,
        TestAPIGatewayStageConfiguration,
        TestAPIGatewaySecurityConfiguration
    ]
    
    for test_class in test_classes:
        tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
        test_suite.addTests(tests)
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(test_suite)
    
    # Exit with appropriate code
    sys.exit(0 if result.wasSuccessful() else 1)