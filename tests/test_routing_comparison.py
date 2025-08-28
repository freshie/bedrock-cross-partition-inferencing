#!/usr/bin/env python3
"""
Routing Comparison Tests

This module runs both internet and VPN routing tests and provides
a comprehensive comparison of the two approaches.
"""

import json
import os
import sys
import time
from datetime import datetime
from typing import Dict, Any, List

# Import our test modules
from test_internet_routing import InternetRoutingTester
from test_vpn_routing import VPNRoutingTester

class RoutingComparisonTester:
    """Compare internet and VPN routing approaches"""
    
    def __init__(self):
        self.project_name = os.environ.get('PROJECT_NAME', 'cross-partition-inference')
        self.environment = os.environ.get('ENVIRONMENT', 'dev')
        self.start_time = datetime.utcnow()
        
        # Test results
        self.internet_results = None
        self.vpn_results = None
        self.comparison_results = {}
    
    def run_internet_tests(self) -> Dict[str, Any]:
        """Run internet routing tests"""
        print("🌐 Running Internet Routing Tests")
        print("=" * 60)
        
        try:
            internet_tester = InternetRoutingTester()
            
            # Check if API Gateway is configured
            if not internet_tester.api_gateway_url:
                print("⚠️ API Gateway URL not configured, skipping internet tests")
                return {
                    'test_suite': 'internet_routing',
                    'skipped': True,
                    'reason': 'API Gateway URL not configured',
                    'total_tests': 0,
                    'successful_tests': 0,
                    'failed_tests': 0,
                    'success_rate': 0
                }
            
            return internet_tester.run_all_tests()
        
        except Exception as e:
            print(f"❌ Internet routing tests failed: {str(e)}")
            return {
                'test_suite': 'internet_routing',
                'error': str(e),
                'total_tests': 0,
                'successful_tests': 0,
                'failed_tests': 0,
                'success_rate': 0
            }
    
    def run_vpn_tests(self) -> Dict[str, Any]:
        """Run VPN routing tests"""
        print("\n🔗 Running VPN Routing Tests")
        print("=" * 60)
        
        try:
            vpn_tester = VPNRoutingTester()
            
            # Check if Lambda function is configured
            if not vpn_tester.lambda_function_name and not vpn_tester.vpn_config.get('lambda_function_name'):
                print("⚠️ Lambda function not configured, skipping VPN tests")
                return {
                    'test_suite': 'vpn_routing',
                    'skipped': True,
                    'reason': 'Lambda function not configured',
                    'total_tests': 0,
                    'successful_tests': 0,
                    'failed_tests': 0,
                    'success_rate': 0
                }
            
            return vpn_tester.run_all_tests()
        
        except Exception as e:
            print(f"❌ VPN routing tests failed: {str(e)}")
            return {
                'test_suite': 'vpn_routing',
                'error': str(e),
                'total_tests': 0,
                'successful_tests': 0,
                'failed_tests': 0,
                'success_rate': 0
            }
    
    def compare_performance(self) -> Dict[str, Any]:
        """Compare performance between routing methods"""
        print("\n⚡ Comparing Performance")
        print("=" * 60)
        
        comparison = {
            'performance_comparison': {},
            'winner': None,
            'analysis': []
        }
        
        try:
            # Extract performance data
            internet_perf = None
            vpn_perf = None
            
            if self.internet_results and not self.internet_results.get('skipped'):
                for test in self.internet_results.get('test_results', []):
                    if test['test_name'] == 'internet_performance_baseline':
                        internet_perf = test
                        break
            
            if self.vpn_results and not self.vpn_results.get('skipped'):
                for test in self.vpn_results.get('test_results', []):
                    if test['test_name'] == 'vpn_performance_baseline':
                        vpn_perf = test
                        break
            
            if internet_perf and vpn_perf:
                internet_avg = internet_perf.get('average_response_time', 0)
                vpn_avg = vpn_perf.get('average_response_time', 0)
                
                comparison['performance_comparison'] = {
                    'internet_routing': {
                        'average_response_time_ms': internet_avg,
                        'min_response_time_ms': internet_perf.get('min_response_time', 0),
                        'max_response_time_ms': internet_perf.get('max_response_time', 0),
                        'successful_requests': internet_perf.get('successful_requests', 0)
                    },
                    'vpn_routing': {
                        'average_response_time_ms': vpn_avg,
                        'min_response_time_ms': vpn_perf.get('min_response_time', 0),
                        'max_response_time_ms': vpn_perf.get('max_response_time', 0),
                        'successful_requests': vpn_perf.get('successful_requests', 0)
                    }
                }
                
                # Determine winner
                if internet_avg < vpn_avg:
                    comparison['winner'] = 'internet'
                    difference = vpn_avg - internet_avg
                    comparison['analysis'].append(f"Internet routing is faster by {difference:.2f}ms on average")
                elif vpn_avg < internet_avg:
                    comparison['winner'] = 'vpn'
                    difference = internet_avg - vpn_avg
                    comparison['analysis'].append(f"VPN routing is faster by {difference:.2f}ms on average")
                else:
                    comparison['winner'] = 'tie'
                    comparison['analysis'].append("Both routing methods have similar performance")
                
                print(f"Internet Routing Average: {internet_avg:.2f}ms")
                print(f"VPN Routing Average: {vpn_avg:.2f}ms")
                print(f"Performance Winner: {comparison['winner'].title()}")
                
                # Additional analysis
                if vpn_avg > internet_avg:
                    overhead = vpn_avg - internet_avg
                    overhead_percent = (overhead / internet_avg) * 100 if internet_avg > 0 else 0
                    comparison['analysis'].append(f"VPN overhead: {overhead:.2f}ms ({overhead_percent:.1f}%)")
                    print(f"VPN Overhead: {overhead:.2f}ms ({overhead_percent:.1f}%)")
            
            elif internet_perf:
                comparison['analysis'].append("Only internet routing performance data available")
                print("Only internet routing performance data available")
            elif vpn_perf:
                comparison['analysis'].append("Only VPN routing performance data available")
                print("Only VPN routing performance data available")
            else:
                comparison['analysis'].append("No performance data available for comparison")
                print("No performance data available for comparison")
        
        except Exception as e:
            comparison['error'] = str(e)
            print(f"❌ Performance comparison failed: {str(e)}")
        
        return comparison
    
    def compare_reliability(self) -> Dict[str, Any]:
        """Compare reliability between routing methods"""
        print("\n🛡️ Comparing Reliability")
        print("=" * 60)
        
        comparison = {
            'reliability_comparison': {},
            'analysis': []
        }
        
        try:
            internet_success_rate = self.internet_results.get('success_rate', 0) if self.internet_results and not self.internet_results.get('skipped') else None
            vpn_success_rate = self.vpn_results.get('success_rate', 0) if self.vpn_results and not self.vpn_results.get('skipped') else None
            
            comparison['reliability_comparison'] = {
                'internet_routing': {
                    'success_rate': internet_success_rate,
                    'total_tests': self.internet_results.get('total_tests', 0) if self.internet_results else 0,
                    'successful_tests': self.internet_results.get('successful_tests', 0) if self.internet_results else 0
                },
                'vpn_routing': {
                    'success_rate': vpn_success_rate,
                    'total_tests': self.vpn_results.get('total_tests', 0) if self.vpn_results else 0,
                    'successful_tests': self.vpn_results.get('successful_tests', 0) if self.vpn_results else 0
                }
            }
            
            if internet_success_rate is not None and vpn_success_rate is not None:
                print(f"Internet Routing Success Rate: {internet_success_rate:.1f}%")
                print(f"VPN Routing Success Rate: {vpn_success_rate:.1f}%")
                
                if internet_success_rate > vpn_success_rate:
                    comparison['reliability_winner'] = 'internet'
                    comparison['analysis'].append(f"Internet routing is more reliable ({internet_success_rate:.1f}% vs {vpn_success_rate:.1f}%)")
                elif vpn_success_rate > internet_success_rate:
                    comparison['reliability_winner'] = 'vpn'
                    comparison['analysis'].append(f"VPN routing is more reliable ({vpn_success_rate:.1f}% vs {internet_success_rate:.1f}%)")
                else:
                    comparison['reliability_winner'] = 'tie'
                    comparison['analysis'].append("Both routing methods have equal reliability")
                
                print(f"Reliability Winner: {comparison['reliability_winner'].title()}")
            
            elif internet_success_rate is not None:
                comparison['analysis'].append(f"Only internet routing reliability data available: {internet_success_rate:.1f}%")
                print(f"Only internet routing reliability data available: {internet_success_rate:.1f}%")
            elif vpn_success_rate is not None:
                comparison['analysis'].append(f"Only VPN routing reliability data available: {vpn_success_rate:.1f}%")
                print(f"Only VPN routing reliability data available: {vpn_success_rate:.1f}%")
            else:
                comparison['analysis'].append("No reliability data available for comparison")
                print("No reliability data available for comparison")
        
        except Exception as e:
            comparison['error'] = str(e)
            print(f"❌ Reliability comparison failed: {str(e)}")
        
        return comparison
    
    def compare_security(self) -> Dict[str, Any]:
        """Compare security aspects between routing methods"""
        print("\n🔒 Comparing Security")
        print("=" * 60)
        
        comparison = {
            'security_comparison': {
                'internet_routing': {
                    'network_isolation': False,
                    'encryption_in_transit': True,
                    'vpc_isolation': False,
                    'audit_trail': True,
                    'security_score': 0
                },
                'vpn_routing': {
                    'network_isolation': True,
                    'encryption_in_transit': True,
                    'vpc_isolation': True,
                    'audit_trail': True,
                    'security_score': 0
                }
            },
            'analysis': []
        }
        
        # Calculate security scores
        internet_score = sum([
            comparison['security_comparison']['internet_routing']['encryption_in_transit'],
            comparison['security_comparison']['internet_routing']['audit_trail']
        ])
        
        vpn_score = sum([
            comparison['security_comparison']['vpn_routing']['network_isolation'],
            comparison['security_comparison']['vpn_routing']['encryption_in_transit'],
            comparison['security_comparison']['vpn_routing']['vpc_isolation'],
            comparison['security_comparison']['vpn_routing']['audit_trail']
        ])
        
        comparison['security_comparison']['internet_routing']['security_score'] = internet_score
        comparison['security_comparison']['vpn_routing']['security_score'] = vpn_score
        
        print("Internet Routing Security Features:")
        print("  ✅ Encryption in transit (HTTPS)")
        print("  ✅ Audit trail")
        print("  ❌ Network isolation")
        print("  ❌ VPC isolation")
        print(f"  Security Score: {internet_score}/4")
        
        print("\nVPN Routing Security Features:")
        print("  ✅ Network isolation (no internet)")
        print("  ✅ Encryption in transit (IPSec + HTTPS)")
        print("  ✅ VPC isolation")
        print("  ✅ Audit trail")
        print(f"  Security Score: {vpn_score}/4")
        
        if vpn_score > internet_score:
            comparison['security_winner'] = 'vpn'
            comparison['analysis'].append(f"VPN routing provides better security ({vpn_score}/4 vs {internet_score}/4)")
            print(f"\n🏆 Security Winner: VPN Routing ({vpn_score}/4 vs {internet_score}/4)")
        else:
            comparison['security_winner'] = 'tie'
            comparison['analysis'].append("Both routing methods have equal security scores")
        
        return comparison
    
    def generate_recommendations(self) -> List[str]:
        """Generate recommendations based on test results"""
        recommendations = []
        
        # Performance recommendations
        if self.comparison_results.get('performance_comparison', {}).get('winner') == 'internet':
            recommendations.append("Consider internet routing for performance-critical applications")
        elif self.comparison_results.get('performance_comparison', {}).get('winner') == 'vpn':
            recommendations.append("VPN routing provides better performance than expected")
        
        # Security recommendations
        if self.comparison_results.get('security_comparison', {}).get('security_winner') == 'vpn':
            recommendations.append("Use VPN routing for security-sensitive workloads")
        
        # Reliability recommendations
        reliability_winner = self.comparison_results.get('reliability_comparison', {}).get('reliability_winner')
        if reliability_winner == 'internet':
            recommendations.append("Internet routing shows higher reliability in current tests")
        elif reliability_winner == 'vpn':
            recommendations.append("VPN routing demonstrates good reliability")
        
        # General recommendations
        if self.internet_results and self.vpn_results:
            if not self.internet_results.get('skipped') and not self.vpn_results.get('skipped'):
                recommendations.append("Both routing methods are functional - choose based on security requirements")
                recommendations.append("Consider implementing routing method selection based on request type")
                recommendations.append("Monitor both approaches in production for optimal performance")
        
        return recommendations
    
    def run_comparison_tests(self) -> Dict[str, Any]:
        """Run complete comparison test suite"""
        print("🔄 Starting Routing Comparison Test Suite")
        print("=" * 80)
        print(f"Project: {self.project_name}")
        print(f"Environment: {self.environment}")
        print(f"Start Time: {self.start_time.isoformat()}")
        print("=" * 80)
        
        # Run individual test suites
        self.internet_results = self.run_internet_tests()
        self.vpn_results = self.run_vpn_tests()
        
        # Run comparisons
        performance_comparison = self.compare_performance()
        reliability_comparison = self.compare_reliability()
        security_comparison = self.compare_security()
        
        # Store comparison results
        self.comparison_results = {
            'performance_comparison': performance_comparison,
            'reliability_comparison': reliability_comparison,
            'security_comparison': security_comparison
        }
        
        # Generate recommendations
        recommendations = self.generate_recommendations()
        
        # Create comprehensive summary
        summary = {
            'comparison_metadata': {
                'project_name': self.project_name,
                'environment': self.environment,
                'start_time': self.start_time.isoformat(),
                'end_time': datetime.utcnow().isoformat(),
                'test_duration_seconds': (datetime.utcnow() - self.start_time).total_seconds()
            },
            'internet_results': self.internet_results,
            'vpn_results': self.vpn_results,
            'comparisons': self.comparison_results,
            'recommendations': recommendations,
            'overall_assessment': self._generate_overall_assessment()
        }
        
        # Print final summary
        self._print_final_summary(summary)
        
        return summary
    
    def _generate_overall_assessment(self) -> Dict[str, Any]:
        """Generate overall assessment of both routing methods"""
        assessment = {
            'internet_routing': {
                'pros': [
                    "Simpler architecture",
                    "Lower latency (potentially)",
                    "Easier to troubleshoot",
                    "No VPN infrastructure required"
                ],
                'cons': [
                    "Less secure (internet exposure)",
                    "No network isolation",
                    "Dependent on internet connectivity",
                    "Higher attack surface"
                ]
            },
            'vpn_routing': {
                'pros': [
                    "Complete network isolation",
                    "Enhanced security (IPSec encryption)",
                    "VPC-native architecture",
                    "Compliance-friendly",
                    "No internet dependencies"
                ],
                'cons': [
                    "More complex architecture",
                    "Additional VPN infrastructure",
                    "Potential higher latency",
                    "More components to monitor"
                ]
            },
            'recommendation': 'vpn'  # Default to VPN for security
        }
        
        # Adjust recommendation based on test results
        if self.comparison_results.get('reliability_comparison', {}).get('reliability_winner') == 'internet':
            if self.comparison_results.get('performance_comparison', {}).get('winner') == 'internet':
                assessment['recommendation'] = 'internet'
        
        return assessment
    
    def _print_final_summary(self, summary: Dict[str, Any]):
        """Print final test summary"""
        print("\n" + "=" * 80)
        print("🏁 ROUTING COMPARISON TEST SUMMARY")
        print("=" * 80)
        
        # Test results summary
        internet_skipped = self.internet_results.get('skipped', False) if self.internet_results else True
        vpn_skipped = self.vpn_results.get('skipped', False) if self.vpn_results else True
        
        print(f"Internet Routing Tests: {'SKIPPED' if internet_skipped else 'COMPLETED'}")
        if not internet_skipped:
            print(f"  Success Rate: {self.internet_results.get('success_rate', 0):.1f}%")
            print(f"  Tests: {self.internet_results.get('successful_tests', 0)}/{self.internet_results.get('total_tests', 0)}")
        
        print(f"VPN Routing Tests: {'SKIPPED' if vpn_skipped else 'COMPLETED'}")
        if not vpn_skipped:
            print(f"  Success Rate: {self.vpn_results.get('success_rate', 0):.1f}%")
            print(f"  Tests: {self.vpn_results.get('successful_tests', 0)}/{self.vpn_results.get('total_tests', 0)}")
        
        # Comparison winners
        print("\n🏆 Comparison Results:")
        perf_winner = self.comparison_results.get('performance_comparison', {}).get('winner', 'unknown')
        rel_winner = self.comparison_results.get('reliability_comparison', {}).get('reliability_winner', 'unknown')
        sec_winner = self.comparison_results.get('security_comparison', {}).get('security_winner', 'unknown')
        
        print(f"  Performance Winner: {perf_winner.title()}")
        print(f"  Reliability Winner: {rel_winner.title()}")
        print(f"  Security Winner: {sec_winner.title()}")
        
        # Overall recommendation
        overall_rec = summary['overall_assessment']['recommendation']
        print(f"\n🎯 Overall Recommendation: {overall_rec.upper()} ROUTING")
        
        # Key recommendations
        print("\n📋 Key Recommendations:")
        for i, rec in enumerate(summary['recommendations'], 1):
            print(f"  {i}. {rec}")
        
        print("\n" + "=" * 80)

def main():
    """Main test execution"""
    comparison_tester = RoutingComparisonTester()
    
    # Run comparison tests
    summary = comparison_tester.run_comparison_tests()
    
    # Save results
    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
    results_file = f"test-results-comparison-{timestamp}.json"
    
    with open(results_file, 'w') as f:
        json.dump(summary, f, indent=2, default=str)
    
    print(f"\n📊 Comprehensive test results saved to: {results_file}")
    
    # Exit with appropriate code
    internet_success = summary['internet_results'].get('success_rate', 0) == 100 if not summary['internet_results'].get('skipped') else True
    vpn_success = summary['vpn_results'].get('success_rate', 0) == 100 if not summary['vpn_results'].get('skipped') else True
    
    if internet_success and vpn_success:
        exit(0)
    else:
        exit(1)

if __name__ == "__main__":
    main()