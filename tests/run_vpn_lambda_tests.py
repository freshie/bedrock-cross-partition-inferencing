#!/usr/bin/env python3
"""
Test runner for VPN Lambda function unit tests
Provides comprehensive test execution with coverage reporting
"""

import unittest
import sys
import os
import json
from datetime import datetime
import coverage

# Add project root to path
project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, project_root)
sys.path.insert(0, os.path.join(project_root, 'lambda'))

class VPNLambdaTestRunner:
    """Test runner for VPN Lambda function tests"""
    
    def __init__(self):
        self.test_results = {
            'timestamp': datetime.utcnow().isoformat(),
            'total_tests': 0,
            'passed_tests': 0,
            'failed_tests': 0,
            'error_tests': 0,
            'skipped_tests': 0,
            'coverage_percentage': 0,
            'test_details': []
        }
    
    def run_tests(self, with_coverage=True, verbose=True):
        """Run all VPN Lambda tests with optional coverage"""
        print("=" * 80)
        print("VPN LAMBDA FUNCTION UNIT TESTS")
        print("=" * 80)
        print(f"Started at: {self.test_results['timestamp']}")
        print()
        
        # Initialize coverage if requested
        cov = None
        if with_coverage:
            cov = coverage.Coverage(
                source=['lambda'],
                omit=[
                    '*/tests/*',
                    '*/test_*',
                    '*/__pycache__/*'
                ]
            )
            cov.start()
        
        try:
            # Discover and run tests
            loader = unittest.TestLoader()
            start_dir = os.path.dirname(__file__)
            suite = loader.discover(start_dir, pattern='test_vpn_lambda_*.py')
            
            # Custom test result class to capture details
            class DetailedTestResult(unittest.TextTestResult):
                def __init__(self, stream, descriptions, verbosity):
                    super().__init__(stream, descriptions, verbosity)
                    self.test_details = []
                
                def addSuccess(self, test):
                    super().addSuccess(test)
                    self.test_details.append({
                        'test': str(test),
                        'status': 'PASSED',
                        'message': None
                    })
                
                def addError(self, test, err):
                    super().addError(test, err)
                    self.test_details.append({
                        'test': str(test),
                        'status': 'ERROR',
                        'message': str(err[1])
                    })
                
                def addFailure(self, test, err):
                    super().addFailure(test, err)
                    self.test_details.append({
                        'test': str(test),
                        'status': 'FAILED',
                        'message': str(err[1])
                    })
                
                def addSkip(self, test, reason):
                    super().addSkip(test, reason)
                    self.test_details.append({
                        'test': str(test),
                        'status': 'SKIPPED',
                        'message': reason
                    })
            
            # Run tests with custom result class
            runner = unittest.TextTestRunner(
                verbosity=2 if verbose else 1,
                resultclass=DetailedTestResult,
                buffer=True
            )
            
            result = runner.run(suite)
            
            # Collect test results
            self.test_results.update({
                'total_tests': result.testsRun,
                'passed_tests': result.testsRun - len(result.failures) - len(result.errors) - len(result.skipped),
                'failed_tests': len(result.failures),
                'error_tests': len(result.errors),
                'skipped_tests': len(result.skipped),
                'test_details': result.test_details if hasattr(result, 'test_details') else []
            })
            
            # Stop coverage and generate report
            if with_coverage and cov:
                cov.stop()
                cov.save()
                
                # Generate coverage report
                coverage_percentage = cov.report(show_missing=True)
                self.test_results['coverage_percentage'] = coverage_percentage
                
                # Generate HTML coverage report
                try:
                    cov.html_report(directory='tests/coverage_html')
                    print(f"\nHTML coverage report generated in: tests/coverage_html/")
                except Exception as e:
                    print(f"Warning: Could not generate HTML coverage report: {e}")
            
            # Print summary
            self._print_summary()
            
            # Save results to file
            self._save_results()
            
            return result.wasSuccessful()
            
        except Exception as e:
            print(f"Error running tests: {e}")
            return False
    
    def _print_summary(self):
        """Print test execution summary"""
        print("\n" + "=" * 80)
        print("TEST EXECUTION SUMMARY")
        print("=" * 80)
        
        results = self.test_results
        print(f"Total Tests:    {results['total_tests']}")
        print(f"Passed:         {results['passed_tests']}")
        print(f"Failed:         {results['failed_tests']}")
        print(f"Errors:         {results['error_tests']}")
        print(f"Skipped:        {results['skipped_tests']}")
        
        if results['coverage_percentage'] > 0:
            print(f"Coverage:       {results['coverage_percentage']:.1f}%")
        
        # Calculate success rate
        if results['total_tests'] > 0:
            success_rate = (results['passed_tests'] / results['total_tests']) * 100
            print(f"Success Rate:   {success_rate:.1f}%")
        
        print()
        
        # Print failed/error test details
        if results['failed_tests'] > 0 or results['error_tests'] > 0:
            print("FAILED/ERROR TESTS:")
            print("-" * 40)
            for detail in results['test_details']:
                if detail['status'] in ['FAILED', 'ERROR']:
                    print(f"❌ {detail['test']}")
                    print(f"   Status: {detail['status']}")
                    if detail['message']:
                        print(f"   Message: {detail['message'][:100]}...")
                    print()
        
        # Overall result
        if results['failed_tests'] == 0 and results['error_tests'] == 0:
            print("🎉 ALL TESTS PASSED!")
        else:
            print("❌ SOME TESTS FAILED")
        
        print("=" * 80)
    
    def _save_results(self):
        """Save test results to JSON file"""
        try:
            results_file = os.path.join('tests', 'vpn_lambda_test_results.json')
            with open(results_file, 'w') as f:
                json.dump(self.test_results, f, indent=2)
            print(f"Test results saved to: {results_file}")
        except Exception as e:
            print(f"Warning: Could not save test results: {e}")

def main():
    """Main test runner function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Run VPN Lambda function unit tests')
    parser.add_argument('--no-coverage', action='store_true', 
                       help='Skip coverage reporting')
    parser.add_argument('--quiet', action='store_true',
                       help='Reduce output verbosity')
    parser.add_argument('--pattern', default='test_vpn_lambda_*.py',
                       help='Test file pattern (default: test_vpn_lambda_*.py)')
    
    args = parser.parse_args()
    
    # Create and run test runner
    runner = VPNLambdaTestRunner()
    success = runner.run_tests(
        with_coverage=not args.no_coverage,
        verbose=not args.quiet
    )
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()