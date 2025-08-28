#!/usr/bin/env python3
"""
Test runner for Internet Lambda function unit tests
Provides comprehensive test execution with coverage reporting and detailed output
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

class InternetLambdaTestRunner:
    """Custom test runner for Internet Lambda function tests"""
    
    def __init__(self):
        self.start_time = None
        self.end_time = None
        self.results = {}
        self.coverage_data = {}
        
    def run_tests_with_coverage(self):
        """Run tests with coverage analysis"""
        print("=" * 80)
        print("INTERNET LAMBDA FUNCTION - UNIT TEST EXECUTION")
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
            from test_internet_lambda_unit import (
                TestInternetLambdaFunction,
                TestInternetLambdaAdvancedFeatures,
                TestInternetLambdaErrorHandling
            )
            
            # Create test suite
            test_suite = unittest.TestSuite()
            
            test_classes = [
                TestInternetLambdaFunction,
                TestInternetLambdaAdvancedFeatures,
                TestInternetLambdaErrorHandling
            ]
            
            total_tests = 0
            for test_class in test_classes:
                tests = unittest.TestLoader().loadTestsFromTestCase(test_class)
                test_suite.addTests(tests)
                total_tests += tests.countTestCases()
            
            print(f"Discovered {total_tests} test cases across {len(test_classes)} test classes")
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
            print(f"❌ Test execution failed: {str(e)}")
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
    
    def _generate_coverage_report(self, cov):
        """Generate coverage report"""
        try:
            print("\n" + "=" * 80)
            print("COVERAGE ANALYSIS")
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
                html_dir = os.path.join(os.path.dirname(__file__), 'coverage_html_internet')
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
        print("TEST EXECUTION SUMMARY")
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
            print("🎉 ALL TESTS PASSED!")
        else:
            print("❌ SOME TESTS FAILED - Review the details above")
        
        print("=" * 80)
    
    def _generate_json_report(self):
        """Generate JSON test report"""
        try:
            report_data = {
                'test_run': {
                    'timestamp': datetime.now().isoformat(),
                    'component': 'internet_lambda',
                    'test_type': 'unit_tests',
                    'execution_time': self.results['execution_time'],
                    'total_tests': self.results['total_tests'],
                    'successful_tests': self.results['successful_tests'],
                    'failed_tests': self.results['failed_tests'],
                    'error_tests': self.results['error_tests'],
                    'skipped_tests': self.results['skipped_tests'],
                    'success_rate': self.results['success_rate']
                },
                'coverage': self.coverage_data,
                'failures': self.results['failures'],
                'errors': self.results['errors']
            }
            
            # Write JSON report
            report_path = os.path.join(os.path.dirname(__file__), 'internet_lambda_test_results.json')
            with open(report_path, 'w') as f:
                json.dump(report_data, f, indent=2)
            
            print(f"📊 JSON test report generated: {report_path}")
            
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
    runner = InternetLambdaTestRunner()
    success = runner.run_tests_with_coverage()
    
    # Exit with appropriate code for CI/CD
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()