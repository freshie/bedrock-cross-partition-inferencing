#!/usr/bin/env python3
"""
Internet Routing Tests

This module tests the original internet-based routing approach for cross-partition
AI inference, ensuring backward compatibility with the existing API Gateway solution.
"""

import json
import boto3
import pytest
import time
import os
from datetime import datetime
from typing import Dict, Any, Optional

class InternetRoutingTester:
    """Test suite for internet-based routing"""
    
    def __init__(self):
        self.govcloud_session = boto3.Session(profile_name='govcloud')
        self.commercial_session = boto3.Session(profile_name='commercial')
        self.project_name = os.environ.get('PROJECT_NAME', 'cross-partition-inference')
        self.environment = os.environ.get('ENVIRONMENT', 'dev')
        
        # API Gateway endpoint (original internet-based approach)
        self.api_gateway_url = os.environ.get('API_GATEWAY_URL')
        self.api_key = os.environ.get('API_GATEWAY_KEY')
        
        # Test configuration
        self.test_results = []
        self.start_time = datetime.utcnow()
    
    def test_api_gateway_endpoint(self) -> Dict[str, Any]:
        """Test API Gateway endpoint availability"""
        print("🌐 Testing API Gateway endpoint availability...")
        
        test_result = {
            'test_name': 'api_gateway_endpoint',
            'routing_method': 'internet',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'response_time_ms': None,
            'error': None
        }
        
        try:
            import requests
            
            start_time = time.time()
            
            # Test basic endpoint availability
            response = requests.get(
                f"{self.api_gateway_url}/health",
                headers={'x-api-key': self.api_key} if self.api_key else {},
                timeout=30
            )
            
            response_time = (time.time() - start_time) * 1000
            test_result['response_time_ms'] = response_time
            
            if response.status_code == 200:
                test_result['success'] = True
                test_result['status_code'] = response.status_code
                print(f"✅ API Gateway endpoint available (Response time: {response_time:.2f}ms)")
            else:
                test_result['error'] = f"HTTP {response.status_code}: {response.text}"
                print(f"❌ API Gateway endpoint returned {response.status_code}")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ API Gateway endpoint test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_internet_bedrock_inference(self) -> Dict[str, Any]:
        """Test Bedrock inference via internet routing"""
        print("🧠 Testing Bedrock inference via internet routing...")
        
        test_result = {
            'test_name': 'internet_bedrock_inference',
            'routing_method': 'internet',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'response_time_ms': None,
            'error': None
        }
        
        try:
            import requests
            
            # Test payload
            test_payload = {
                'model_id': 'anthropic.claude-3-sonnet-20240229-v1:0',
                'prompt': 'Hello, this is a test of internet-based cross-partition connectivity.',
                'max_tokens': 100,
                'routing_method': 'internet'  # Explicitly request internet routing
            }
            
            start_time = time.time()
            
            response = requests.post(
                f"{self.api_gateway_url}/invoke",
                json=test_payload,
                headers={
                    'Content-Type': 'application/json',
                    'x-api-key': self.api_key
                } if self.api_key else {'Content-Type': 'application/json'},
                timeout=60
            )
            
            response_time = (time.time() - start_time) * 1000
            test_result['response_time_ms'] = response_time
            
            if response.status_code == 200:
                response_data = response.json()
                
                # Validate response structure
                if 'response' in response_data and 'metadata' in response_data:
                    test_result['success'] = True
                    test_result['model_id'] = response_data.get('metadata', {}).get('model_id')
                    test_result['routing_method_used'] = response_data.get('metadata', {}).get('routing_method')
                    test_result['response_length'] = len(response_data.get('response', ''))
                    
                    print(f"✅ Internet Bedrock inference successful")
                    print(f"   Response time: {response_time:.2f}ms")
                    print(f"   Model: {test_result['model_id']}")
                    print(f"   Routing: {test_result['routing_method_used']}")
                    print(f"   Response length: {test_result['response_length']} chars")
                else:
                    test_result['error'] = "Invalid response structure"
                    print(f"❌ Invalid response structure: {response_data}")
            else:
                test_result['error'] = f"HTTP {response.status_code}: {response.text}"
                print(f"❌ Bedrock inference failed: {response.status_code}")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ Internet Bedrock inference test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_internet_authentication(self) -> Dict[str, Any]:
        """Test authentication mechanisms for internet routing"""
        print("🔐 Testing internet routing authentication...")
        
        test_result = {
            'test_name': 'internet_authentication',
            'routing_method': 'internet',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'error': None
        }
        
        try:
            import requests
            
            # Test without API key (should fail)
            response_no_key = requests.post(
                f"{self.api_gateway_url}/invoke",
                json={'test': 'no_auth'},
                headers={'Content-Type': 'application/json'},
                timeout=30
            )
            
            # Test with API key (should succeed)
            if self.api_key:
                response_with_key = requests.post(
                    f"{self.api_gateway_url}/invoke",
                    json={'test': 'with_auth'},
                    headers={
                        'Content-Type': 'application/json',
                        'x-api-key': self.api_key
                    },
                    timeout=30
                )
                
                # Authentication working if no-key fails and with-key succeeds
                if response_no_key.status_code == 403 and response_with_key.status_code in [200, 400]:
                    test_result['success'] = True
                    print("✅ Internet routing authentication working correctly")
                else:
                    test_result['error'] = f"Auth test failed: no-key={response_no_key.status_code}, with-key={response_with_key.status_code}"
                    print(f"❌ Authentication test failed")
            else:
                # No API key configured, just check if endpoint is accessible
                if response_no_key.status_code in [200, 400]:
                    test_result['success'] = True
                    print("✅ Internet routing accessible (no API key configured)")
                else:
                    test_result['error'] = f"Endpoint not accessible: {response_no_key.status_code}"
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ Internet authentication test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_internet_audit_trail(self) -> Dict[str, Any]:
        """Test audit trail for internet routing"""
        print("📋 Testing internet routing audit trail...")
        
        test_result = {
            'test_name': 'internet_audit_trail',
            'routing_method': 'internet',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'error': None
        }
        
        try:
            # Make a test request first
            import requests
            
            test_payload = {
                'model_id': 'anthropic.claude-3-sonnet-20240229-v1:0',
                'prompt': 'Audit trail test for internet routing',
                'max_tokens': 50,
                'routing_method': 'internet'
            }
            
            response = requests.post(
                f"{self.api_gateway_url}/invoke",
                json=test_payload,
                headers={
                    'Content-Type': 'application/json',
                    'x-api-key': self.api_key
                } if self.api_key else {'Content-Type': 'application/json'},
                timeout=60
            )
            
            if response.status_code == 200:
                # Check if audit trail was created
                # This would typically check DynamoDB for the request log
                dynamodb = self.govcloud_session.resource('dynamodb', region_name='us-gov-west-1')
                table_name = f"{self.project_name}-request-log-{self.environment}"
                
                try:
                    table = dynamodb.Table(table_name)
                    
                    # Query recent items (last 5 minutes)
                    from boto3.dynamodb.conditions import Key
                    import time
                    
                    current_time = int(time.time())
                    five_minutes_ago = current_time - 300
                    
                    response_items = table.scan(
                        FilterExpression=Key('timestamp').gte(five_minutes_ago),
                        Limit=10
                    )
                    
                    if response_items['Items']:
                        # Check if any items have internet routing method
                        internet_requests = [
                            item for item in response_items['Items']
                            if item.get('routing_method') == 'internet'
                        ]
                        
                        if internet_requests:
                            test_result['success'] = True
                            test_result['audit_records_found'] = len(internet_requests)
                            print(f"✅ Internet routing audit trail working ({len(internet_requests)} records found)")
                        else:
                            test_result['error'] = "No internet routing audit records found"
                            print("❌ No internet routing audit records found")
                    else:
                        test_result['error'] = "No recent audit records found"
                        print("❌ No recent audit records found")
                
                except Exception as e:
                    test_result['error'] = f"Failed to check audit trail: {str(e)}"
                    print(f"❌ Failed to check audit trail: {str(e)}")
            else:
                test_result['error'] = f"Test request failed: {response.status_code}"
                print(f"❌ Test request failed: {response.status_code}")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ Internet audit trail test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def test_internet_performance_baseline(self) -> Dict[str, Any]:
        """Test performance baseline for internet routing"""
        print("⚡ Testing internet routing performance baseline...")
        
        test_result = {
            'test_name': 'internet_performance_baseline',
            'routing_method': 'internet',
            'start_time': datetime.utcnow().isoformat(),
            'success': False,
            'response_times': [],
            'average_response_time': None,
            'error': None
        }
        
        try:
            import requests
            
            test_payload = {
                'model_id': 'anthropic.claude-3-sonnet-20240229-v1:0',
                'prompt': 'Performance test for internet routing',
                'max_tokens': 50,
                'routing_method': 'internet'
            }
            
            response_times = []
            successful_requests = 0
            
            # Run 5 test requests to get baseline
            for i in range(5):
                try:
                    start_time = time.time()
                    
                    response = requests.post(
                        f"{self.api_gateway_url}/invoke",
                        json=test_payload,
                        headers={
                            'Content-Type': 'application/json',
                            'x-api-key': self.api_key
                        } if self.api_key else {'Content-Type': 'application/json'},
                        timeout=60
                    )
                    
                    response_time = (time.time() - start_time) * 1000
                    
                    if response.status_code == 200:
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
                
                print(f"✅ Internet routing performance baseline established")
                print(f"   Average: {test_result['average_response_time']:.2f}ms")
                print(f"   Min: {test_result['min_response_time']:.2f}ms")
                print(f"   Max: {test_result['max_response_time']:.2f}ms")
                print(f"   Success rate: {successful_requests}/5")
            else:
                test_result['error'] = "No successful requests"
                print("❌ No successful requests for performance baseline")
        
        except Exception as e:
            test_result['error'] = str(e)
            print(f"❌ Internet performance baseline test failed: {str(e)}")
        
        test_result['end_time'] = datetime.utcnow().isoformat()
        self.test_results.append(test_result)
        return test_result
    
    def run_all_tests(self) -> Dict[str, Any]:
        """Run all internet routing tests"""
        print("🌐 Starting Internet Routing Test Suite")
        print("=" * 50)
        
        # Run all tests
        self.test_api_gateway_endpoint()
        self.test_internet_bedrock_inference()
        self.test_internet_authentication()
        self.test_internet_audit_trail()
        self.test_internet_performance_baseline()
        
        # Generate summary
        total_tests = len(self.test_results)
        successful_tests = sum(1 for result in self.test_results if result['success'])
        
        summary = {
            'test_suite': 'internet_routing',
            'total_tests': total_tests,
            'successful_tests': successful_tests,
            'failed_tests': total_tests - successful_tests,
            'success_rate': (successful_tests / total_tests) * 100 if total_tests > 0 else 0,
            'start_time': self.start_time.isoformat(),
            'end_time': datetime.utcnow().isoformat(),
            'test_results': self.test_results
        }
        
        print("\n" + "=" * 50)
        print("🌐 Internet Routing Test Summary")
        print("=" * 50)
        print(f"Total Tests: {total_tests}")
        print(f"Successful: {successful_tests}")
        print(f"Failed: {total_tests - successful_tests}")
        print(f"Success Rate: {summary['success_rate']:.1f}%")
        
        if successful_tests == total_tests:
            print("✅ All internet routing tests passed!")
        else:
            print("❌ Some internet routing tests failed")
            for result in self.test_results:
                if not result['success']:
                    print(f"   - {result['test_name']}: {result['error']}")
        
        return summary

def main():
    """Main test execution"""
    tester = InternetRoutingTester()
    
    # Check if API Gateway URL is configured
    if not tester.api_gateway_url:
        print("❌ API_GATEWAY_URL environment variable not set")
        print("Please set the API Gateway URL for internet routing tests")
        return
    
    # Run tests
    summary = tester.run_all_tests()
    
    # Save results
    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
    results_file = f"test-results-internet-{timestamp}.json"
    
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