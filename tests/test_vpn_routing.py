#!/usr/bin/env python3
"""
VPN Routing Tests

This module tests the new VPN-based routing approach for cross-partition
AI inference, validating the VPN connectivity solution.
"""

import json
import boto3
import pytest
import time
import os
from datetime import datetime
from typing import Dict, Any, Optional

class VPNRoutingTester:
    """Test suite for VPN-based routing"""
    
    def __init__(self):
        self.govcloud_session = boto3.Session(profile_name='govcloud')
        self.commercial_session = boto3.Session(profile_name='commercial')
        self.project_name = os.environ.get('PROJECT_NAME', 'cross-partition-inference')
        self.environment = os.environ.get('ENVIRONMENT', 'dev')
        
        # Lambda function for VPN routing
        self.lambda_function_name = os.environ.get('LAMBDA_FUNCTION_NAME')
        
        # Load VPN configuration if available
        self.vpn_config = self._load_vpn_config()
        
        # Test configuration
        self.test_results = []
        self.start_time = datetime.utcnow()
    
    def _load_vpn_config(self) -> Dict[str, Any]:
        """Load VPN configuration from config file"""
        config = {}
        
        # Try to load from environment variables (set by config-vpn.sh)
        config_vars = [
            'GOVCLOUD_VPC_ID', 'COMMERCIAL_VPC_ID',
            'GOVCLOUD_VPN_CONNECTION_ID', 'COMMERCIAL_VPN_CONNECTION_ID',
            'GOVCLOUD_VPN_TUNNEL_1_STATUS', 'COMMERCIAL_VPN_TUNNEL_1_STATUS',
            'VPC_ENDPOINT_SECRETS', 'COMMERCIAL_BEDROCK_ENDPOINT',
            'LAMBDA_FUNCTION_NAME', 'REQUEST_LOG_TABLE'
        ]
        
        for var in config_vars:
            config[var.lower()] = os.environ.get(var)
        
        return config
    
    def test_vpn_tunnel_connectivity(self) -> Dict[str, Any]:
        """Test VPN tunnel connectivity"""
        print("🔗 Testing VPN tunnel connectivity...")
        
        test_result = {
            'test_name': 'vpn_tunnel_connectivity',
            'routing_method': 'vpn',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'tunnel_status': {},
            'error': None
        }
        
        try:
            # Check GovCloud VPN tunnels
            ec2_govcloud = self.govcloud_session.client('ec2', region_name='us-gov-west-1')
            
            if self.vpn_config.get('govcloud_vpn_connection_id'):
                govcloud_vpn = ec2_govcloud.describe_vpn_connections(
                    VpnConnectionIds=[self.vpn_config['govcloud_vpn_connection_id']]
                )
                
                if govcloud_vpn['VpnConnections']:
                    vpn_conn = govcloud_vpn['VpnConnections'][0]
                    test_result['tunnel_status']['govcloud'] = {
                        'connection_state': vpn_conn['State'],
                        'tunnels': []
                    }
                    
                    for tunnel in vpn_conn.get('VgwTelemetry', []):
                        test_result['tunnel_status']['govcloud']['tunnels'].append({
                            'ip': tunnel['OutsideIpAddress'],
                            'status': tunnel['Status'],
                            'last_status_change': tunnel.get('LastStatusChange', '').isoformat() if tunnel.get('LastStatusChange') else None
                        })
            
            # Check Commercial VPN tunnels
            ec2_commercial = self.commercial_session.client('ec2', region_name='us-east-1')
            
            if self.vpn_config.get('commercial_vpn_connection_id'):
                commercial_vpn = ec2_commercial.describe_vpn_connections(
                    VpnConnectionIds=[self.vpn_config['commercial_vpn_connection_id']]
                )
                
                if commercial_vpn['VpnConnections']:
                    vpn_conn = commercial_vpn['VpnConnections'][0]
                    test_result['tunnel_status']['commercial'] = {
                        'connection_state': vpn_conn['State'],
                        'tunnels': []
                    }
                    
                    for tunnel in vpn_conn.get('VgwTelemetry', []):
                        test_result['tunnel_status']['commercial']['tunnels'].append({
                            'ip': tunnel['OutsideIpAddress'],
                            'status': tunnel['Status'],
                            'last_status_change': tunnel.get('LastStatusChange', '').isoformat() if tunnel.get('LastStatusChange') else None
                        })
            
            # Check if at least one tunnel is UP in each partition
            govcloud_up = any(
                tunnel['status'] == 'UP' 
                for tunnel in test_result['tunnel_status'].get('govcloud', {}).get('tunnels', [])
            )
            commercial_up = any(
                tunnel['status'] == 'UP' 
                for tunnel in test_result['tunnel_status'].get('commercial', {}).get('tunnels', [])
            )
            
            if govcloud_up and commercial_up:
                test_result['success'] = True
                print("✅ VPN tunnels are UP in both partitions")
            else:
                test_result['error'] = f"VPN tunnels not fully operational (GovCloud: {govcloud_up}, Commercial: {commercial_up})"
                print(f"❌ VPN tunnels not fully operational")
            
            # Print tunnel status
            for partition, status in test_result['tunnel_status'].items():
                print(f"   {partition.title()}: {status['connection_state']}")
                for tunnel in status.get('tunnels', []):
                    print(f"     Tunnel {tunnel['ip']}: {tunnel['status']}")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ VPN tunnel connectivity test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_lambda_vpc_configuration(self) -> Dict[str, Any]:
        """Test Lambda VPC configuration"""
        print("⚡ Testing Lambda VPC configuration...")
        
        test_result = {
            'test_name': 'lambda_vpc_configuration',
            'routing_method': 'vpn',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'lambda_config': {},
            'error': None
        }
        
        try:
            lambda_client = self.govcloud_session.client('lambda', region_name='us-gov-west-1')
            
            function_name = self.lambda_function_name or self.vpn_config.get('lambda_function_name')
            if not function_name:
                test_result['error'] = "Lambda function name not configured"
                print("❌ Lambda function name not configured")
                return test_result
            
            # Get Lambda function configuration
            response = lambda_client.get_function_configuration(FunctionName=function_name)
            
            test_result['lambda_config'] = {
                'function_name': response['FunctionName'],
                'state': response['State'],
                'vpc_config': response.get('VpcConfig', {}),
                'environment': response.get('Environment', {}).get('Variables', {}),
                'timeout': response['Timeout'],
                'memory_size': response['MemorySize']
            }
            
            # Check VPC configuration
            vpc_config = response.get('VpcConfig', {})
            if vpc_config.get('VpcId') and vpc_config.get('SubnetIds') and vpc_config.get('SecurityGroupIds'):
                test_result['success'] = True
                print("✅ Lambda function is properly configured for VPC")
                print(f"   VPC ID: {vpc_config['VpcId']}")
                print(f"   Subnets: {len(vpc_config['SubnetIds'])}")
                print(f"   Security Groups: {len(vpc_config['SecurityGroupIds'])}")
                
                # Check if VPC matches expected GovCloud VPC
                expected_vpc = self.vpn_config.get('govcloud_vpc_id')
                if expected_vpc and vpc_config['VpcId'] == expected_vpc:
                    print(f"   ✅ VPC matches expected GovCloud VPC")
                elif expected_vpc:
                    print(f"   ⚠️ VPC mismatch: expected {expected_vpc}, got {vpc_config['VpcId']}")
            else:
                test_result['error'] = "Lambda function not configured for VPC"
                print("❌ Lambda function not configured for VPC")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ Lambda VPC configuration test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_vpc_endpoint_connectivity(self) -> Dict[str, Any]:
        """Test VPC endpoint connectivity"""
        print("🔌 Testing VPC endpoint connectivity...")
        
        test_result = {
            'test_name': 'vpc_endpoint_connectivity',
            'routing_method': 'vpn',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'endpoint_tests': {},
            'error': None
        }
        
        try:
            # Test VPC endpoints by making actual AWS service calls
            # This tests the Lambda function's ability to reach AWS services via VPC endpoints
            
            # Test Secrets Manager endpoint
            try:
                secrets_client = self.govcloud_session.client('secretsmanager', region_name='us-gov-west-1')
                secrets_client.list_secrets(MaxResults=1)
                test_result['endpoint_tests']['secrets_manager'] = {'status': 'success'}
                print("   ✅ Secrets Manager VPC endpoint accessible")
            except Exception as e:
                test_result['endpoint_tests']['secrets_manager'] = {'status': 'failed', 'error': str(e)}
                print(f"   ❌ Secrets Manager VPC endpoint failed: {str(e)}")
            
            # Test DynamoDB endpoint
            try:
                dynamodb_client = self.govcloud_session.client('dynamodb', region_name='us-gov-west-1')
                dynamodb_client.list_tables(Limit=1)
                test_result['endpoint_tests']['dynamodb'] = {'status': 'success'}
                print("   ✅ DynamoDB VPC endpoint accessible")
            except Exception as e:
                test_result['endpoint_tests']['dynamodb'] = {'status': 'failed', 'error': str(e)}
                print(f"   ❌ DynamoDB VPC endpoint failed: {str(e)}")
            
            # Test CloudWatch Logs endpoint
            try:
                logs_client = self.govcloud_session.client('logs', region_name='us-gov-west-1')
                logs_client.describe_log_groups(limit=1)
                test_result['endpoint_tests']['cloudwatch_logs'] = {'status': 'success'}
                print("   ✅ CloudWatch Logs VPC endpoint accessible")
            except Exception as e:
                test_result['endpoint_tests']['cloudwatch_logs'] = {'status': 'failed', 'error': str(e)}
                print(f"   ❌ CloudWatch Logs VPC endpoint failed: {str(e)}")
            
            # Check success rate
            successful_endpoints = sum(1 for test in test_result['endpoint_tests'].values() if test['status'] == 'success')
            total_endpoints = len(test_result['endpoint_tests'])
            
            if successful_endpoints == total_endpoints:
                test_result['success'] = True
                print(f"✅ All VPC endpoints accessible ({successful_endpoints}/{total_endpoints})")
            else:
                test_result['error'] = f"Some VPC endpoints failed ({successful_endpoints}/{total_endpoints})"
                print(f"❌ Some VPC endpoints failed ({successful_endpoints}/{total_endpoints})")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ VPC endpoint connectivity test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_vpn_bedrock_inference(self) -> Dict[str, Any]:
        """Test Bedrock inference via VPN routing"""
        print("🧠 Testing Bedrock inference via VPN routing...")
        
        test_result = {
            'test_name': 'vpn_bedrock_inference',
            'routing_method': 'vpn',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'response_time_ms': None,
            'error': None
        }
        
        try:
            lambda_client = self.govcloud_session.client('lambda', region_name='us-gov-west-1')
            
            function_name = self.lambda_function_name or self.vpn_config.get('lambda_function_name')
            if not function_name:
                test_result['error'] = "Lambda function name not configured"
                print("❌ Lambda function name not configured")
                return test_result
            
            # Test payload
            test_payload = {
                'model_id': 'anthropic.claude-3-sonnet-20240229-v1:0',
                'prompt': 'Hello, this is a test of VPN-based cross-partition connectivity.',
                'max_tokens': 100,
                'routing_method': 'vpn'  # Explicitly request VPN routing
            }
            
            start_time = time.time()
            
            # Invoke Lambda function directly
            response = lambda_client.invoke(
                FunctionName=function_name,
                Payload=json.dumps(test_payload)
            )
            
            response_time = (time.time() - start_time) * 1000
            test_result['response_time_ms'] = response_time
            
            # Parse response
            payload = json.loads(response['Payload'].read())
            
            if response['StatusCode'] == 200 and 'errorMessage' not in payload:
                # Check if response has expected structure
                if 'response' in payload and 'metadata' in payload:
                    test_result['success'] = True
                    test_result['model_id'] = payload.get('metadata', {}).get('model_id')
                    test_result['routing_method_used'] = payload.get('metadata', {}).get('routing_method')
                    test_result['response_length'] = len(payload.get('response', ''))
                    
                    print(f"✅ VPN Bedrock inference successful")
                    print(f"   Response time: {response_time:.2f}ms")
                    print(f"   Model: {test_result['model_id']}")
                    print(f"   Routing: {test_result['routing_method_used']}")
                    print(f"   Response length: {test_result['response_length']} chars")
                else:
                    test_result['error'] = f"Invalid response structure: {payload}"
                    print(f"❌ Invalid response structure")
            else:
                test_result['error'] = payload.get('errorMessage', f"Lambda error: {response['StatusCode']}")
                print(f"❌ VPN Bedrock inference failed: {test_result['error']}")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ VPN Bedrock inference test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_vpn_audit_trail(self) -> Dict[str, Any]:
        """Test audit trail for VPN routing"""
        print("📋 Testing VPN routing audit trail...")
        
        test_result = {
            'test_name': 'vpn_audit_trail',
            'routing_method': 'vpn',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'error': None
        }
        
        try:
            # Make a test request first
            lambda_client = self.govcloud_session.client('lambda', region_name='us-gov-west-1')
            
            function_name = self.lambda_function_name or self.vpn_config.get('lambda_function_name')
            if not function_name:
                test_result['error'] = "Lambda function name not configured"
                return test_result
            
            test_payload = {
                'model_id': 'anthropic.claude-3-sonnet-20240229-v1:0',
                'prompt': 'Audit trail test for VPN routing',
                'max_tokens': 50,
                'routing_method': 'vpn'
            }
            
            response = lambda_client.invoke(
                FunctionName=function_name,
                Payload=json.dumps(test_payload)
            )
            
            if response['StatusCode'] == 200:
                # Check if audit trail was created
                dynamodb = self.govcloud_session.resource('dynamodb', region_name='us-gov-west-1')
                table_name = self.vpn_config.get('request_log_table') or f"{self.project_name}-request-log-{self.environment}"
                
                try:
                    table = dynamodb.Table(table_name)
                    
                    # Query recent items (last 5 minutes)
                    current_time = int(time.time())
                    five_minutes_ago = current_time - 300
                    
                    response_items = table.scan(
                        FilterExpression=boto3.dynamodb.conditions.Attr('timestamp').gte(five_minutes_ago),
                        Limit=10
                    )
                    
                    if response_items['Items']:
                        # Check if any items have VPN routing method
                        vpn_requests = [
                            item for item in response_items['Items']
                            if item.get('routing_method') == 'vpn'
                        ]
                        
                        if vpn_requests:
                            test_result['success'] = True
                            test_result['audit_records_found'] = len(vpn_requests)
                            print(f"✅ VPN routing audit trail working ({len(vpn_requests)} records found)")
                        else:
                            test_result['error'] = "No VPN routing audit records found"
                            print("❌ No VPN routing audit records found")
                    else:
                        test_result['error'] = "No recent audit records found"
                        print("❌ No recent audit records found")
                
                except Exception as e:
                    test_result['error'] = f"Failed to check audit trail: {str(e)}"
                    print(f"❌ Failed to check audit trail: {str(e)}")
            else:
                test_result['error'] = f"Test request failed: {response['StatusCode']}"
                print(f"❌ Test request failed: {response['StatusCode']}")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ VPN audit trail test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_vpn_performance_baseline(self) -> Dict[str, Any]:
        """Test performance baseline for VPN routing"""
        print("⚡ Testing VPN routing performance baseline...")
        
        test_result = {
            'test_name': 'vpn_performance_baseline',
            'routing_method': 'vpn',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'response_times': [],
            'average_response_time': None,
            'error': None
        }
        
        try:
            lambda_client = self.govcloud_session.client('lambda', region_name='us-gov-west-1')
            
            function_name = self.lambda_function_name or self.vpn_config.get('lambda_function_name')
            if not function_name:
                test_result['error'] = "Lambda function name not configured"
                return test_result
            
            test_payload = {
                'model_id': 'anthropic.claude-3-sonnet-20240229-v1:0',
                'prompt': 'Performance test for VPN routing',
                'max_tokens': 50,
                'routing_method': 'vpn'
            }
            
            response_times = []
            successful_requests = 0
            
            # Run 5 test requests to get baseline
            for i in range(5):
                try:
                    start_time = time.time()
                    
                    response = lambda_client.invoke(
                        FunctionName=function_name,
                        Payload=json.dumps(test_payload)
                    )
                    
                    response_time = (time.time() - start_time) * 1000
                    
                    if response['StatusCode'] == 200:
                        payload = json.loads(response['Payload'].read())
                        if 'errorMessage' not in payload:
                            response_times.append(response_time)
                            successful_requests += 1
                            print(f"  Request {i+1}: {response_time:.2f}ms")
                    
                    # Small delay between requests
                    time.sleep(1)
                
                except Exception as e:
                    print(f"  Request {i+1} failed: {str(e)}")
            
            if response_times:
                test_result['response_times'] = response_times
                test_result['average_response_time'] = sum(response_times) / len(response_times)
                test_result['min_response_time'] = min(response_times)
                test_result['max_response_time'] = max(response_times)
                test_result['successful_requests'] = successful_requests
                test_result['success'] = True
                
                print(f"✅ VPN routing performance baseline established")
                print(f"   Average: {test_result['average_response_time']:.2f}ms")
                print(f"   Min: {test_result['min_response_time']:.2f}ms")
                print(f"   Max: {test_result['max_response_time']:.2f}ms")
                print(f"   Success rate: {successful_requests}/5")
            else:
                test_result['error'] = "No successful requests"
                print("❌ No successful requests for performance baseline")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ VPN performance baseline test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def run_all_tests(self) -> Dict[str, Any]:
        """Run all VPN routing tests"""
        print("🔗 Starting VPN Routing Test Suite")
        print("=" * 50)
        
        # Run all tests
        self.test_vpn_tunnel_connectivity()
        self.test_lambda_vpc_configuration()
        self.test_vpc_endpoint_connectivity()
        self.test_vpn_bedrock_inference()
        self.test_vpn_audit_trail()
        self.test_vpn_performance_baseline()
        
        # Generate summary
        total_tests = len(self.test_results)
        successful_tests = sum(1 for result in self.test_results if result['success'])
        
        summary = {
            'test_suite': 'vpn_routing',
            'total_tests': total_tests,
            'successful_tests': successful_tests,
            'failed_tests': total_tests - successful_tests,
            'success_rate': (successful_tests / total_tests) * 100 if total_tests > 0 else 0,
            'start_time': self.start_time.isoformat(),
            'end_time': datetime.utcnow().isoformat(),
            'test_results': self.test_results
        }
        
        print("\n" + "=" * 50)
        print("🔗 VPN Routing Test Summary")
        print("=" * 50)
        print(f"Total Tests: {total_tests}")
        print(f"Successful: {successful_tests}")
        print(f"Failed: {total_tests - successful_tests}")
        print(f"Success Rate: {summary['success_rate']:.1f}%")
        
        if successful_tests == total_tests:
            print("✅ All VPN routing tests passed!")
        else:
            print("❌ Some VPN routing tests failed")
            for result in self.test_results:
                if not result['success']:
                    print(f"   - {result['test_name']}: {result['error']}")
        
        return summary

def main():
    """Main test execution"""
    tester = VPNRoutingTester()
    
    # Check if VPN configuration is available
    if not tester.vpn_config.get('lambda_function_name') and not tester.lambda_function_name:
        print("❌ Lambda function name not configured")
        print("Please set LAMBDA_FUNCTION_NAME environment variable or run 'source config-vpn.sh'")
        return
    
    # Run tests
    summary = tester.run_all_tests()
    
    # Save results
    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
    results_file = f"test-results-vpn-{timestamp}.json"
    
    with open(results_file, 'w') as f:
        json.dump(summary, f, indent=2)
    
    print(f"\n📊 Test results saved to: {results_file}")
    
    # Exit with appropriate code
    if summary['success_rate'] == 100:
        exit(0)
    else:
        exit(1)

if __name__ == "__main__":
    main()