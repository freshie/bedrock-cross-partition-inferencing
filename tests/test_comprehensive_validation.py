#!/usr/bin/env python3

"""
Comprehensive validation tests for dual routing API Gateway system.

This test suite validates both routing methods are functional, performs
performance comparisons, and includes load testing capabilities.
"""

import asyncio
import json
import time
import statistics
import concurrent.futures
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
from datetime import datetime, timedelta
import requests
import boto3
import pytest
from botocore.exceptions import ClientError


@dataclass
class TestConfig:
    """Configuration for comprehensive validation tests."""
    api_gateway_url: str
    api_key: str
    internet_path: str = "/v1/bedrock/invoke-model"
    vpn_path: str = "/v1/vpn/bedrock/invoke-model"
    models_path: str = "/v1/bedrock/models"
    vpn_models_path: str = "/v1/vpn/bedrock/models"
    health_path: str = "/v1/bedrock"
    vpn_health_path: str = "/v1/vpn/bedrock"
    test_model_id: str = "anthropic.claude-3-haiku-20240307-v1:0"
    timeout: int = 30
    max_retries: int = 3
    load_test_duration: int = 60  # seconds
    load_test_rps: int = 10  # requests per second


@dataclass
class TestResult:
    """Result of a single test request."""
    success: bool
    status_code: int
    response_time: float
    routing_method: str
    error_message: Optional[str] = None
    response_data: Optional[Dict] = None


@dataclass
class PerformanceMetrics:
    """Performance metrics for a test run."""
    total_requests: int
    successful_requests: int
    failed_requests: int
    success_rate: float
    avg_response_time: float
    min_response_time: float
    max_response_time: float
    p50_response_time: float
    p95_response_time: float
    p99_response_time: float
    requests_per_second: float
    error_distribution: Dict[str, int]


class ComprehensiveValidator:
    """Comprehensive validation test suite for dual routing system."""
    
    def __init__(self, config: TestConfig):
        self.config = config
        self.session = requests.Session()
        self.session.headers.update({
            'X-API-Key': config.api_key,
            'Content-Type': 'application/json',
            'User-Agent': 'DualRoutingValidator/1.0'
        })
        
        # CloudWatch client for metrics validation
        self.cloudwatch = boto3.client('cloudwatch')
    
    def _make_request(self, method: str, path: str, data: Optional[Dict] = None) -> TestResult:
        """Make a single HTTP request and return test result."""
        url = f"{self.config.api_gateway_url}{path}"
        start_time = time.time()
        
        try:
            if method.upper() == 'GET':
                response = self.session.get(url, timeout=self.config.timeout)
            elif method.upper() == 'POST':
                response = self.session.post(url, json=data, timeout=self.config.timeout)
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")
            
            response_time = (time.time() - start_time) * 1000  # Convert to milliseconds
            
            # Determine routing method from path
            routing_method = "vpn" if "/vpn/" in path else "internet"
            
            # Parse response data
            response_data = None
            try:
                response_data = response.json()
            except json.JSONDecodeError:
                pass
            
            return TestResult(
                success=response.status_code < 400,
                status_code=response.status_code,
                response_time=response_time,
                routing_method=routing_method,
                response_data=response_data,
                error_message=None if response.status_code < 400 else response.text
            )
            
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            routing_method = "vpn" if "/vpn/" in path else "internet"
            
            return TestResult(
                success=False,
                status_code=0,
                response_time=response_time,
                routing_method=routing_method,
                error_message=str(e)
            )
    
    def _calculate_metrics(self, results: List[TestResult]) -> PerformanceMetrics:
        """Calculate performance metrics from test results."""
        if not results:
            return PerformanceMetrics(0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, {})
        
        total_requests = len(results)
        successful_requests = sum(1 for r in results if r.success)
        failed_requests = total_requests - successful_requests
        success_rate = (successful_requests / total_requests) * 100
        
        response_times = [r.response_time for r in results]
        avg_response_time = statistics.mean(response_times)
        min_response_time = min(response_times)
        max_response_time = max(response_times)
        
        # Calculate percentiles
        sorted_times = sorted(response_times)
        p50_response_time = statistics.median(sorted_times)
        p95_response_time = sorted_times[int(0.95 * len(sorted_times))]
        p99_response_time = sorted_times[int(0.99 * len(sorted_times))]
        
        # Calculate RPS (approximate)
        if response_times:
            test_duration = max(response_times) / 1000  # Convert to seconds
            requests_per_second = total_requests / max(test_duration, 1)
        else:
            requests_per_second = 0.0
        
        # Error distribution
        error_distribution = {}
        for result in results:
            if not result.success:
                error_key = f"{result.status_code}: {result.error_message[:50] if result.error_message else 'Unknown'}"
                error_distribution[error_key] = error_distribution.get(error_key, 0) + 1
        
        return PerformanceMetrics(
            total_requests=total_requests,
            successful_requests=successful_requests,
            failed_requests=failed_requests,
            success_rate=success_rate,
            avg_response_time=avg_response_time,
            min_response_time=min_response_time,
            max_response_time=max_response_time,
            p50_response_time=p50_response_time,
            p95_response_time=p95_response_time,
            p99_response_time=p99_response_time,
            requests_per_second=requests_per_second,
            error_distribution=error_distribution
        )
    
    def test_health_endpoints(self) -> Dict[str, TestResult]:
        """Test health endpoints for both routing methods."""
        print("Testing health endpoints...")
        
        results = {}
        
        # Test Internet health endpoint
        results['internet_health'] = self._make_request('GET', self.config.health_path)
        
        # Test VPN health endpoint
        results['vpn_health'] = self._make_request('GET', self.config.vpn_health_path)
        
        return results
    
    def test_model_listing(self) -> Dict[str, TestResult]:
        """Test model listing endpoints for both routing methods."""
        print("Testing model listing endpoints...")
        
        results = {}
        
        # Test Internet model listing
        results['internet_models'] = self._make_request('GET', self.config.models_path)
        
        # Test VPN model listing
        results['vpn_models'] = self._make_request('GET', self.config.vpn_models_path)
        
        return results
    
    def test_model_inference(self) -> Dict[str, TestResult]:
        """Test model inference for both routing methods."""
        print("Testing model inference...")
        
        test_payload = {
            "modelId": self.config.test_model_id,
            "body": {
                "messages": [
                    {
                        "role": "user",
                        "content": "Hello! This is a test message for validation. Please respond with a brief acknowledgment."
                    }
                ],
                "max_tokens": 50,
                "temperature": 0.7
            }
        }
        
        results = {}
        
        # Test Internet inference
        results['internet_inference'] = self._make_request('POST', self.config.internet_path, test_payload)
        
        # Test VPN inference
        results['vpn_inference'] = self._make_request('POST', self.config.vpn_path, test_payload)
        
        return results
    
    def test_error_handling(self) -> Dict[str, TestResult]:
        """Test error handling for both routing methods."""
        print("Testing error handling...")
        
        results = {}
        
        # Test with invalid model ID
        invalid_payload = {
            "modelId": "invalid-model-id",
            "body": {
                "messages": [{"role": "user", "content": "Test"}],
                "max_tokens": 50
            }
        }
        
        results['internet_invalid_model'] = self._make_request('POST', self.config.internet_path, invalid_payload)
        results['vpn_invalid_model'] = self._make_request('POST', self.config.vpn_path, invalid_payload)
        
        # Test with malformed payload
        malformed_payload = {
            "modelId": self.config.test_model_id,
            "body": {
                "invalid_field": "test"
            }
        }
        
        results['internet_malformed'] = self._make_request('POST', self.config.internet_path, malformed_payload)
        results['vpn_malformed'] = self._make_request('POST', self.config.vpn_path, malformed_payload)
        
        # Test without API key
        original_headers = self.session.headers.copy()
        del self.session.headers['X-API-Key']
        
        test_payload = {
            "modelId": self.config.test_model_id,
            "body": {
                "messages": [{"role": "user", "content": "Test"}],
                "max_tokens": 50
            }
        }
        
        results['internet_no_auth'] = self._make_request('POST', self.config.internet_path, test_payload)
        results['vpn_no_auth'] = self._make_request('POST', self.config.vpn_path, test_payload)
        
        # Restore headers
        self.session.headers = original_headers
        
        return results
    
    def performance_comparison_test(self, num_requests: int = 50) -> Dict[str, PerformanceMetrics]:
        """Run performance comparison test between routing methods."""
        print(f"Running performance comparison test with {num_requests} requests per method...")
        
        test_payload = {
            "modelId": self.config.test_model_id,
            "body": {
                "messages": [
                    {
                        "role": "user",
                        "content": "Performance test message. Please provide a brief response."
                    }
                ],
                "max_tokens": 30,
                "temperature": 0.5
            }
        }
        
        # Test Internet routing
        print("Testing Internet routing performance...")
        internet_results = []
        for i in range(num_requests):
            result = self._make_request('POST', self.config.internet_path, test_payload)
            internet_results.append(result)
            if (i + 1) % 10 == 0:
                print(f"  Completed {i + 1}/{num_requests} Internet requests")
        
        # Test VPN routing
        print("Testing VPN routing performance...")
        vpn_results = []
        for i in range(num_requests):
            result = self._make_request('POST', self.config.vpn_path, test_payload)
            vpn_results.append(result)
            if (i + 1) % 10 == 0:
                print(f"  Completed {i + 1}/{num_requests} VPN requests")
        
        return {
            'internet': self._calculate_metrics(internet_results),
            'vpn': self._calculate_metrics(vpn_results)
        }
    
    def load_test(self, routing_method: str = 'both') -> Dict[str, PerformanceMetrics]:
        """Run load test for specified routing method(s)."""
        print(f"Running load test for {routing_method} routing method(s)...")
        print(f"Duration: {self.config.load_test_duration}s, Target RPS: {self.config.load_test_rps}")
        
        test_payload = {
            "modelId": self.config.test_model_id,
            "body": {
                "messages": [
                    {
                        "role": "user",
                        "content": "Load test message. Brief response please."
                    }
                ],
                "max_tokens": 20,
                "temperature": 0.3
            }
        }
        
        def run_load_test_for_path(path: str, method_name: str) -> List[TestResult]:
            """Run load test for a specific path."""
            results = []
            start_time = time.time()
            request_interval = 1.0 / self.config.load_test_rps
            
            with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
                futures = []
                
                while time.time() - start_time < self.config.load_test_duration:
                    future = executor.submit(self._make_request, 'POST', path, test_payload)
                    futures.append(future)
                    time.sleep(request_interval)
                
                # Collect results
                for future in concurrent.futures.as_completed(futures):
                    try:
                        result = future.result(timeout=self.config.timeout)
                        results.append(result)
                    except Exception as e:
                        # Create error result
                        error_result = TestResult(
                            success=False,
                            status_code=0,
                            response_time=0.0,
                            routing_method=method_name,
                            error_message=str(e)
                        )
                        results.append(error_result)
            
            return results
        
        load_test_results = {}
        
        if routing_method in ['internet', 'both']:
            print("Running Internet routing load test...")
            internet_results = run_load_test_for_path(self.config.internet_path, 'internet')
            load_test_results['internet'] = self._calculate_metrics(internet_results)
        
        if routing_method in ['vpn', 'both']:
            print("Running VPN routing load test...")
            vpn_results = run_load_test_for_path(self.config.vpn_path, 'vpn')
            load_test_results['vpn'] = self._calculate_metrics(vpn_results)
        
        return load_test_results
    
    def functional_equivalence_test(self) -> Dict[str, bool]:
        """Test functional equivalence between routing methods."""
        print("Testing functional equivalence between routing methods...")
        
        test_cases = [
            {
                "name": "simple_query",
                "payload": {
                    "modelId": self.config.test_model_id,
                    "body": {
                        "messages": [{"role": "user", "content": "What is 2+2?"}],
                        "max_tokens": 20
                    }
                }
            },
            {
                "name": "complex_query",
                "payload": {
                    "modelId": self.config.test_model_id,
                    "body": {
                        "messages": [
                            {"role": "user", "content": "Explain the concept of cloud computing in one sentence."}
                        ],
                        "max_tokens": 50,
                        "temperature": 0.5
                    }
                }
            }
        ]
        
        equivalence_results = {}
        
        for test_case in test_cases:
            print(f"  Testing {test_case['name']}...")
            
            # Get responses from both methods
            internet_result = self._make_request('POST', self.config.internet_path, test_case['payload'])
            vpn_result = self._make_request('POST', self.config.vpn_path, test_case['payload'])
            
            # Check if both succeeded
            both_successful = internet_result.success and vpn_result.success
            
            # Check response structure similarity
            structure_similar = False
            if both_successful and internet_result.response_data and vpn_result.response_data:
                internet_keys = set(internet_result.response_data.keys())
                vpn_keys = set(vpn_result.response_data.keys())
                structure_similar = internet_keys == vpn_keys
            
            equivalence_results[test_case['name']] = {
                'both_successful': both_successful,
                'structure_similar': structure_similar,
                'internet_status': internet_result.status_code,
                'vpn_status': vpn_result.status_code,
                'internet_response_time': internet_result.response_time,
                'vpn_response_time': vpn_result.response_time
            }
        
        return equivalence_results
    
    def validate_cloudwatch_metrics(self) -> Dict[str, bool]:
        """Validate that CloudWatch metrics are being published."""
        print("Validating CloudWatch metrics...")
        
        # Define metrics to check
        metrics_to_check = [
            {
                'namespace': 'CrossPartition/DualRouting',
                'metric_name': 'CrossPartitionRequests',
                'dimensions': [{'Name': 'RoutingMethod', 'Value': 'internet'}]
            },
            {
                'namespace': 'CrossPartition/DualRouting',
                'metric_name': 'CrossPartitionRequests',
                'dimensions': [{'Name': 'RoutingMethod', 'Value': 'vpn'}]
            },
            {
                'namespace': 'CrossPartition/DualRouting',
                'metric_name': 'CrossPartitionLatency',
                'dimensions': [{'Name': 'RoutingMethod', 'Value': 'internet'}]
            },
            {
                'namespace': 'CrossPartition/DualRouting',
                'metric_name': 'CrossPartitionLatency',
                'dimensions': [{'Name': 'RoutingMethod', 'Value': 'vpn'}]
            }
        ]
        
        validation_results = {}
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        for metric in metrics_to_check:
            metric_key = f"{metric['namespace']}/{metric['metric_name']}/{metric['dimensions'][0]['Value']}"
            
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace=metric['namespace'],
                    MetricName=metric['metric_name'],
                    Dimensions=metric['dimensions'],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Sum', 'Average']
                )
                
                has_data = len(response['Datapoints']) > 0
                validation_results[metric_key] = has_data
                
            except ClientError as e:
                print(f"  Error checking metric {metric_key}: {e}")
                validation_results[metric_key] = False
        
        return validation_results
    
    def run_comprehensive_validation(self) -> Dict:
        """Run all validation tests and return comprehensive results."""
        print("Starting comprehensive validation test suite...")
        print("=" * 60)
        
        start_time = time.time()
        results = {}
        
        try:
            # 1. Health endpoint tests
            results['health_tests'] = self.test_health_endpoints()
            
            # 2. Model listing tests
            results['model_listing_tests'] = self.test_model_listing()
            
            # 3. Model inference tests
            results['inference_tests'] = self.test_model_inference()
            
            # 4. Error handling tests
            results['error_handling_tests'] = self.test_error_handling()
            
            # 5. Performance comparison tests
            results['performance_comparison'] = self.performance_comparison_test()
            
            # 6. Functional equivalence tests
            results['functional_equivalence'] = self.functional_equivalence_test()
            
            # 7. Load tests
            results['load_tests'] = self.load_test()
            
            # 8. CloudWatch metrics validation
            results['cloudwatch_metrics'] = self.validate_cloudwatch_metrics()
            
        except Exception as e:
            results['error'] = str(e)
            print(f"Error during comprehensive validation: {e}")
        
        total_time = time.time() - start_time
        results['test_duration'] = total_time
        results['timestamp'] = datetime.utcnow().isoformat()
        
        print("=" * 60)
        print(f"Comprehensive validation completed in {total_time:.2f} seconds")
        
        return results


def print_validation_summary(results: Dict):
    """Print a summary of validation results."""
    print("\n" + "=" * 60)
    print("COMPREHENSIVE VALIDATION SUMMARY")
    print("=" * 60)
    
    # Health tests summary
    if 'health_tests' in results:
        print("\n🏥 Health Tests:")
        for test_name, result in results['health_tests'].items():
            status = "✅ PASS" if result.success else "❌ FAIL"
            print(f"  {test_name}: {status} ({result.status_code}, {result.response_time:.0f}ms)")
    
    # Model listing tests summary
    if 'model_listing_tests' in results:
        print("\n📋 Model Listing Tests:")
        for test_name, result in results['model_listing_tests'].items():
            status = "✅ PASS" if result.success else "❌ FAIL"
            print(f"  {test_name}: {status} ({result.status_code}, {result.response_time:.0f}ms)")
    
    # Inference tests summary
    if 'inference_tests' in results:
        print("\n🧠 Inference Tests:")
        for test_name, result in results['inference_tests'].items():
            status = "✅ PASS" if result.success else "❌ FAIL"
            print(f"  {test_name}: {status} ({result.status_code}, {result.response_time:.0f}ms)")
    
    # Performance comparison summary
    if 'performance_comparison' in results:
        print("\n⚡ Performance Comparison:")
        for method, metrics in results['performance_comparison'].items():
            print(f"  {method.upper()} Routing:")
            print(f"    Success Rate: {metrics.success_rate:.1f}%")
            print(f"    Avg Response Time: {metrics.avg_response_time:.0f}ms")
            print(f"    P95 Response Time: {metrics.p95_response_time:.0f}ms")
            print(f"    Requests/Second: {metrics.requests_per_second:.1f}")
    
    # Load test summary
    if 'load_tests' in results:
        print("\n🔥 Load Test Results:")
        for method, metrics in results['load_tests'].items():
            print(f"  {method.upper()} Routing:")
            print(f"    Total Requests: {metrics.total_requests}")
            print(f"    Success Rate: {metrics.success_rate:.1f}%")
            print(f"    Avg Response Time: {metrics.avg_response_time:.0f}ms")
            print(f"    P95 Response Time: {metrics.p95_response_time:.0f}ms")
    
    # Functional equivalence summary
    if 'functional_equivalence' in results:
        print("\n🔄 Functional Equivalence:")
        for test_name, result in results['functional_equivalence'].items():
            both_ok = "✅" if result['both_successful'] else "❌"
            structure_ok = "✅" if result['structure_similar'] else "❌"
            print(f"  {test_name}: {both_ok} Both Successful, {structure_ok} Structure Similar")
    
    # CloudWatch metrics summary
    if 'cloudwatch_metrics' in results:
        print("\n📊 CloudWatch Metrics:")
        for metric_name, has_data in results['cloudwatch_metrics'].items():
            status = "✅ ACTIVE" if has_data else "❌ NO DATA"
            print(f"  {metric_name}: {status}")
    
    # Overall summary
    print(f"\n⏱️  Total Test Duration: {results.get('test_duration', 0):.2f} seconds")
    print(f"🕐 Test Timestamp: {results.get('timestamp', 'Unknown')}")
    
    print("\n" + "=" * 60)


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Comprehensive validation tests for dual routing system")
    parser.add_argument("--api-url", required=True, help="API Gateway URL")
    parser.add_argument("--api-key", required=True, help="API Key for authentication")
    parser.add_argument("--model-id", default="anthropic.claude-3-haiku-20240307-v1:0", help="Test model ID")
    parser.add_argument("--load-test-duration", type=int, default=60, help="Load test duration in seconds")
    parser.add_argument("--load-test-rps", type=int, default=10, help="Load test requests per second")
    parser.add_argument("--output-file", help="Output file for detailed results (JSON)")
    
    args = parser.parse_args()
    
    # Create test configuration
    config = TestConfig(
        api_gateway_url=args.api_url,
        api_key=args.api_key,
        test_model_id=args.model_id,
        load_test_duration=args.load_test_duration,
        load_test_rps=args.load_test_rps
    )
    
    # Run comprehensive validation
    validator = ComprehensiveValidator(config)
    results = validator.run_comprehensive_validation()
    
    # Print summary
    print_validation_summary(results)
    
    # Save detailed results if requested
    if args.output_file:
        with open(args.output_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        print(f"\nDetailed results saved to: {args.output_file}")