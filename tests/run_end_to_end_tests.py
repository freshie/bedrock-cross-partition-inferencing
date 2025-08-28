#!/usr/bin/env python3
"""
Test runner for end-to-end dual routing tests
Provides comprehensive test execution for complete routing flow validation
"""

import unittest
import sys
import os
import json
import time
from datetime import datetime
from io import StringIO

# Add lambda directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lambda'))

try:
    import coverage
    COVERAGE_AVAILABLE = True
except ImportError:
    COVERAGE_AVAILABLE = False
    print("Warning: coverage package not available. Install with: pip install coverage")

class EndToEndTestRunner:
    """Custom test runner for end-to-end dual routing tests"""
    
    def __init__(self):
        self.start_time = None
        self.end_time = None
        self.results = {}
        self.coverage_data = {}
        self.performance_metrics = {}
        
    def run_tests_with_coverage(self):
        """Run end-to-end tests with coverage analysis"""
        print("=" * 80)
        print("DUAL ROUTING SYSTEM - END-TO-END TEST EXECUTION")
        print("=" * 80)
        print(f"Test execution started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        # Initialize coverage if available
        cov = None
        if COVERAGE_AVAILABLE:
            cov = coverage.Coverage(
                source=['lambda'],
                omit=[
                    '*/tests/*',
                    '*/test_*',
                    '*/__pycache__/*',
                    '*/venv/*',
                    '*/env/*'
                ]
            )
            cov.start()
            print("✓ Coverage analysis enabled")
        else:
            print("⚠ Coverage analysis disabled (coverage package not installed)")
        
        print()
        
        # Discover and run tests
        self.start_time = time.time()
        
        try:
            # Import test modules
            from test_end_to_end_routing import (
                TestEndToEndInternetRouting,
                TestEndToEndVPNRouting,
                TestEndToEndRoutingComparison
            )
            
            # Create test suite
            test_suite = unittest.TestSuite()
            
            test_classes = [
                TestEndToEndInternetRouting,
                TestEndToEndVPNRouting,
                TestEndToEndRoutingComparison
            ]
            
            total_tests = 0
            for test_class in test_classes:
                tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
                test_suite.addTests(tests)
                total_tests += tests.countTestCases()
            
            print(f"Discovered {total_tests} end-to-end test cases across {len(test_classes)} test classes")
            print()
            
            # Run tests with custom result handler
            stream = StringIO()
            runner = unittest.TextTestRunner(
                stream=stream,
                verbosity=2,
                resultclass=DetailedTestResult
            )
            
            test_result = runner.run(test_suite)
            
            self.end_time = time.time()
            
            # Stop coverage
            if cov:
                cov.stop()
                cov.save()
            
            # Process results
            self._process_results(test_result, stream.getvalue())
            
            # Generate coverage report
            if cov:
                self._generate_coverage_report(cov)
            
            # Print summary
            self._print_summary()
            
            # Generate JSON report
            self._generate_json_report()
            
            return test_result.wasSuccessful()
            
        except Exception as e:
            print(f"❌ End-to-end test execution failed: {str(e)}")
            if cov:
                cov.stop()
            return False
    
    def _process_results(self, test_result, output):
        """Process test results and extract detailed information"""
        execution_time = self.end_time - self.start_time
        
        self.results = {
            'execution_time': execution_time,
            'total_tests': test_result.testsRun,
            'successful_tests': test_result.testsRun - len(test_result.failures) - len(test_result.errors),
            'failed_tests': len(test_result.failures),
            'error_tests': len(test_result.errors),
            'skipped_tests': len(test_result.skipped) if hasattr(test_result, 'skipped') else 0,
            'success_rate': ((test_result.testsRun - len(test_result.failures) - len(test_result.errors)) / test_result.testsRun * 100) if test_result.testsRun > 0 else 0,
            'failures': [],
            'errors': [],
            'output': output
        }
        
        # Process failures
        for test, traceback in test_result.failures:
            self.results['failures'].append({
                'test': str(test),
                'traceback': traceback
            })
        
        # Process errors
        for test, traceback in test_result.errors:
            self.results['errors'].append({
                'test': str(test),
                'traceback': traceback
            })
        
        # Extract performance metrics from output
        self._extract_performance_metrics(output)
    
    def _extract_performance_metrics(self, output):
        """Extract performance metrics from test output"""
        self.performance_metrics = {
            'internet_routing_latency': None,
            'vpn_routing_latency': None,
            'latency_difference': None,
            'performance_comparison_available': False
        }
        
        # Parse performance comparison output
        lines = output.split('\n')
        for i, line in enumerate(lines):
            if 'Performance Comparison:' in line:
                self.performance_metrics['performance_comparison_available'] = True
                # Extract latency metrics from subsequent lines
                for j in range(i+1, min(i+5, len(lines))):
                    if 'Internet routing latency:' in lines[j]:
                        try:
                            latency = float(lines[j].split(':')[1].strip().replace('ms', ''))
                            self.performance_metrics['internet_routing_latency'] = latency
                        except:
                            pass
                    elif 'VPN routing latency:' in lines[j]:
                        try:
                            latency = float(lines[j].split(':')[1].strip().replace('ms', ''))
                            self.performance_metrics['vpn_routing_latency'] = latency
                        except:
                            pass
                    elif 'Latency difference:' in lines[j]:
                        try:
                            diff = float(lines[j].split(':')[1].strip().replace('ms', ''))
                            self.performance_metrics['latency_difference'] = diff
                        except:
                            pass
                break
    
    def _generate_coverage_report(self, cov):
        """Generate coverage report"""
        try:
            print("\n" + "=" * 80)
            print("END-TO-END TEST COVERAGE ANALYSIS")
            print("=" * 80)
            
            # Generate coverage data
            coverage_data = {}
            
            # Get coverage report
            stream = StringIO()
            cov.report(file=stream, show_missing=True)
            coverage_report = stream.getvalue()
            
            print(coverage_report)
            
            # Get coverage percentage
            total_coverage = cov.report(file=StringIO())
            
            # Store coverage data
            self.coverage_data = {
                'total_coverage': total_coverage,
                'report': coverage_report,
                'missing_lines': {}
            }
            
            # Generate HTML report if possible
            try:
                html_dir = os.path.join(os.path.dirname(__file__), 'coverage_html_e2e')
                cov.html_report(directory=html_dir)
                print(f"\n✓ HTML coverage report generated: {html_dir}/index.html")
                self.coverage_data['html_report_path'] = html_dir
            except Exception as e:
                print(f"⚠ Could not generate HTML coverage report: {str(e)}")
            
        except Exception as e:
            print(f"⚠ Coverage report generation failed: {str(e)}")
    
    def _print_summary(self):
        """Print test execution summary"""
        print("\n" + "=" * 80)
        print("END-TO-END TEST EXECUTION SUMMARY")
        print("=" * 80)
        
        print(f"Total Tests:      {self.results['total_tests']}")
        print(f"Successful:       {self.results['successful_tests']} ✓")
        print(f"Failed:           {self.results['failed_tests']} ❌")
        print(f"Errors:           {self.results['error_tests']} ⚠")
        print(f"Skipped:          {self.results['skipped_tests']} ⏭")
        print(f"Success Rate:     {self.results['success_rate']:.1f}%")
        print(f"Execution Time:   {self.results['execution_time']:.2f} seconds")
        
        if self.coverage_data:
            print(f"Code Coverage:    {self.coverage_data.get('total_coverage', 'N/A')}%")
        
        print()
        
        # Print test categories summary
        print("END-TO-END TEST CATEGORIES EXECUTED:")
        print("-" * 40)
        print("✓ Complete internet routing flow validation")
        print("✓ Complete VPN routing flow validation")
        print("✓ Authentication and error handling end-to-end")
        print("✓ Network failure scenarios")
        print("✓ VPC endpoint connectivity testing")
        print("✓ Functional equivalence comparison")
        print("✓ Performance comparison between routing methods")
        print("✓ Error handling consistency validation")
        print()
        
        # Print performance metrics if available
        if self.performance_metrics.get('performance_comparison_available'):
            print("PERFORMANCE COMPARISON RESULTS:")
            print("-" * 40)
            if self.performance_metrics['internet_routing_latency']:
                print(f"Internet Routing Latency: {self.performance_metrics['internet_routing_latency']:.2f}ms")
            if self.performance_metrics['vpn_routing_latency']:
                print(f"VPN Routing Latency:      {self.performance_metrics['vpn_routing_latency']:.2f}ms")
            if self.performance_metrics['latency_difference']:
                print(f"Latency Difference:       {self.performance_metrics['latency_difference']:.2f}ms")
            print()
        
        # Print failures and errors
        if self.results['failures']:
            print("FAILED TESTS:")
            print("-" * 40)
            for failure in self.results['failures']:
                print(f"❌ {failure['test']}")
            print()
        
        if self.results['errors']:
            print("ERROR TESTS:")
            print("-" * 40)
            for error in self.results['errors']:
                print(f"⚠ {error['test']}")
            print()
        
        # Overall result
        if self.results['failed_tests'] == 0 and self.results['error_tests'] == 0:
            print("🎉 ALL END-TO-END TESTS PASSED!")
            print("✓ Complete internet routing flow validated")
            print("✓ Complete VPN routing flow validated")
            print("✓ Functional equivalence between routing methods confirmed")
            print("✓ Error handling consistency verified")
            print("✓ Performance characteristics measured")
            print("")
            print("The dual routing system is fully functional and ready for production deployment.")
        else:
            print("❌ SOME END-TO-END TESTS FAILED")
            print("⚠ The dual routing system may have issues - Review details above")
            print("")
            print("Common issues to investigate:")
            print("- Lambda function integration problems")
            print("- Bedrock API connectivity issues")
            print("- VPC endpoint configuration problems")
            print("- Authentication and authorization failures")
        
        print("=" * 80)
    
    def _generate_json_report(self):
        """Generate JSON test report"""
        try:
            report_data = {
                'test_run': {
                    'timestamp': datetime.now().isoformat(),
                    'component': 'dual_routing_end_to_end',
                    'test_type': 'end_to_end_tests',
                    'execution_time': self.results['execution_time'],
                    'total_tests': self.results['total_tests'],
                    'successful_tests': self.results['successful_tests'],
                    'failed_tests': self.results['failed_tests'],
                    'error_tests': self.results['error_tests'],
                    'skipped_tests': self.results['skipped_tests'],
                    'success_rate': self.results['success_rate']
                },
                'test_categories': {
                    'internet_routing_e2e': 'Complete internet routing flow validation',
                    'vpn_routing_e2e': 'Complete VPN routing flow validation',
                    'authentication_e2e': 'Authentication and error handling end-to-end',
                    'network_failure_scenarios': 'Network failure scenarios',
                    'vpc_endpoint_testing': 'VPC endpoint connectivity testing',
                    'functional_equivalence': 'Functional equivalence comparison',
                    'performance_comparison': 'Performance comparison between routing methods',
                    'error_consistency': 'Error handling consistency validation'
                },
                'performance_metrics': self.performance_metrics,
                'coverage': self.coverage_data,
                'failures': self.results['failures'],
                'errors': self.results['errors']
            }
            
            # Write JSON report
            report_path = os.path.join(os.path.dirname(__file__), 'end_to_end_test_results.json')
            with open(report_path, 'w') as f:
                json.dump(report_data, f, indent=2)
            
            print(f"📊 JSON end-to-end test report generated: {report_path}")
            
        except Exception as e:
            print(f"⚠ Could not generate JSON report: {str(e)}")


class DetailedTestResult(unittest.TextTestResult):
    """Custom test result class for detailed reporting"""
    
    def __init__(self, stream, descriptions, verbosity):
        super().__init__(stream, descriptions, verbosity)
        self.test_start_time = {}
    
    def startTest(self, test):
        super().startTest(test)
        self.test_start_time[test] = time.time()
        if self.verbosity > 1:
            self.stream.write(f"Running {test} ... ")
            self.stream.flush()
    
    def addSuccess(self, test):
        super().addSuccess(test)
        if self.verbosity > 1:
            elapsed = time.time() - self.test_start_time.get(test, 0)
            self.stream.write(f"✓ ({elapsed:.3f}s)\n")
    
    def addError(self, test, err):
        super().addError(test, err)
        if self.verbosity > 1:
            elapsed = time.time() - self.test_start_time.get(test, 0)
            self.stream.write(f"ERROR ({elapsed:.3f}s)\n")
    
    def addFailure(self, test, err):
        super().addFailure(test, err)
        if self.verbosity > 1:
            elapsed = time.time() - self.test_start_time.get(test, 0)
            self.stream.write(f"FAIL ({elapsed:.3f}s)\n")


def main():
    """Main test execution function"""
    runner = EndToEndTestRunner()
    success = runner.run_tests_with_coverage()
    
    # Exit with appropriate code for CI/CD
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()