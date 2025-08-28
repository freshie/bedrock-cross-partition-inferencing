#!/bin/bash

# Performance comparison testing script for dual routing system
# This script provides detailed performance analysis between routing methods

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
API_GATEWAY_STACK=""
TEST_MODEL_ID="anthropic.claude-3-haiku-20240307-v1:0"
NUM_REQUESTS="100"
CONCURRENT_REQUESTS="10"
OUTPUT_DIR="outputs"
DETAILED_ANALYSIS="true"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Performance comparison testing script for dual routing system

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --api-gateway-stack NAME    API Gateway CloudFormation stack name (required)
    --test-model-id ID          Model ID for testing (default: anthropic.claude-3-haiku-20240307-v1:0)
    --num-requests NUM          Number of requests per routing method (default: 100)
    --concurrent-requests NUM   Number of concurrent requests (default: 10)
    --output-dir DIR            Output directory for reports (default: outputs)
    --skip-detailed-analysis    Skip detailed statistical analysis
    --help                     Show this help message

Examples:
    # Basic performance comparison
    $0 --api-gateway-stack my-api-gateway-stack

    # Detailed comparison with more requests
    $0 --api-gateway-stack my-api-gateway-stack \\
       --num-requests 200 --concurrent-requests 20

    # Quick comparison
    $0 --api-gateway-stack my-api-gateway-stack \\
       --num-requests 50 --skip-detailed-analysis

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --govcloud-profile)
            GOVCLOUD_PROFILE="$2"
            shift 2
            ;;
        --api-gateway-stack)
            API_GATEWAY_STACK="$2"
            shift 2
            ;;
        --test-model-id)
            TEST_MODEL_ID="$2"
            shift 2
            ;;
        --num-requests)
            NUM_REQUESTS="$2"
            shift 2
            ;;
        --concurrent-requests)
            CONCURRENT_REQUESTS="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --skip-detailed-analysis)
            DETAILED_ANALYSIS="false"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$API_GATEWAY_STACK" ]]; then
    log_error "API Gateway stack name is required. Use --api-gateway-stack parameter."
    exit 1
fi

# Validate AWS CLI profile
if ! aws sts get-caller-identity --profile "$GOVCLOUD_PROFILE" >/dev/null 2>&1; then
    log_error "Cannot access AWS with profile '$GOVCLOUD_PROFILE'. Please check your AWS configuration."
    exit 1
fi

# Get AWS region
AWS_REGION=$(aws configure get region --profile "$GOVCLOUD_PROFILE")
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="us-gov-west-1"
    log_warning "No region configured for profile '$GOVCLOUD_PROFILE', using default: $AWS_REGION"
fi

# Create output directory
mkdir -p "$PROJECT_ROOT/$OUTPUT_DIR"

log_info "Starting performance comparison for dual routing system..."
log_info "  Project: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Region: $AWS_REGION"
log_info "  API Gateway Stack: $API_GATEWAY_STACK"
log_info "  Requests per method: $NUM_REQUESTS"
log_info "  Concurrent requests: $CONCURRENT_REQUESTS"

# Function to get CloudFormation output
get_stack_output() {
    local stack_name="$1"
    local output_key="$2"
    
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --profile "$GOVCLOUD_PROFILE" \
        --region "$AWS_REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='$output_key'].OutputValue" \
        --output text 2>/dev/null || echo ""
}

# Get API Gateway information
log_info "Retrieving API Gateway information..."

API_GATEWAY_URL=$(get_stack_output "$API_GATEWAY_STACK" "ApiGatewayUrl")
if [[ -z "$API_GATEWAY_URL" ]]; then
    API_GATEWAY_URL=$(get_stack_output "$API_GATEWAY_STACK" "ApiUrl")
fi

API_KEY=$(get_stack_output "$API_GATEWAY_STACK" "ApiKeyValue")
if [[ -z "$API_KEY" ]]; then
    API_KEY=$(get_stack_output "$API_GATEWAY_STACK" "ApiKey")
fi

# Validate we got the required information
if [[ -z "$API_GATEWAY_URL" ]]; then
    log_error "Could not retrieve API Gateway URL from stack: $API_GATEWAY_STACK"
    exit 1
fi

if [[ -z "$API_KEY" ]]; then
    log_error "Could not retrieve API Key from stack: $API_GATEWAY_STACK"
    exit 1
fi

log_success "Retrieved API Gateway information:"
log_info "  URL: $API_GATEWAY_URL"
log_info "  API Key: ${API_KEY:0:10}..."

# Generate timestamp for this test run
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TEST_RUN_ID="${PROJECT_NAME}_${ENVIRONMENT}_perfcomp_${TIMESTAMP}"

# Create performance comparison Python script
PERF_COMP_SCRIPT="$PROJECT_ROOT/$OUTPUT_DIR/perf_comparison_${TIMESTAMP}.py"

cat > "$PERF_COMP_SCRIPT" << 'EOF'
#!/usr/bin/env python3

import asyncio
import aiohttp
import time
import json
import statistics
import sys
from datetime import datetime
from typing import List, Dict, Tuple
from dataclasses import dataclass
import argparse
import concurrent.futures
from scipy import stats
import numpy as np

@dataclass
class PerfTestConfig:
    api_url: str
    api_key: str
    num_requests: int
    concurrent_requests: int
    test_model_id: str
    detailed_analysis: bool = True

@dataclass
class RequestResult:
    timestamp: float
    success: bool
    status_code: int
    response_time: float
    routing_method: str
    error: str = None
    response_size: int = 0

class PerformanceComparator:
    def __init__(self, config: PerfTestConfig):
        self.config = config
        self.internet_results: List[RequestResult] = []
        self.vpn_results: List[RequestResult] = []
        
    async def make_request(self, session: aiohttp.ClientSession, path: str, routing_method: str) -> RequestResult:
        """Make a single HTTP request."""
        url = f"{self.config.api_url}{path}"
        
        payload = {
            "modelId": self.config.test_model_id,
            "body": {
                "messages": [
                    {
                        "role": "user",
                        "content": f"Performance test message {int(time.time())}. Please provide a brief response for comparison testing."
                    }
                ],
                "max_tokens": 50,
                "temperature": 0.5
            }
        }
        
        headers = {
            'X-API-Key': self.config.api_key,
            'Content-Type': 'application/json'
        }
        
        start_time = time.time()
        
        try:
            async with session.post(url, json=payload, headers=headers, timeout=60) as response:
                response_time = (time.time() - start_time) * 1000
                response_text = await response.text()
                response_size = len(response_text.encode('utf-8'))
                
                return RequestResult(
                    timestamp=start_time,
                    success=response.status < 400,
                    status_code=response.status,
                    response_time=response_time,
                    routing_method=routing_method,
                    response_size=response_size
                )
                
        except Exception as e:
            response_time = (time.time() - start_time) * 1000
            return RequestResult(
                timestamp=start_time,
                success=False,
                status_code=0,
                response_time=response_time,
                routing_method=routing_method,
                error=str(e)
            )
    
    async def run_performance_test(self, path: str, routing_method: str) -> List[RequestResult]:
        """Run performance test for a specific routing method."""
        print(f"Testing {routing_method} routing ({self.config.num_requests} requests)...")
        
        connector = aiohttp.TCPConnector(limit=self.config.concurrent_requests * 2)
        timeout = aiohttp.ClientTimeout(total=60)
        
        results = []
        
        async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
            # Create semaphore to limit concurrent requests
            semaphore = asyncio.Semaphore(self.config.concurrent_requests)
            
            async def bounded_request():
                async with semaphore:
                    return await self.make_request(session, path, routing_method)
            
            # Create all tasks
            tasks = [bounded_request() for _ in range(self.config.num_requests)]
            
            # Execute tasks and collect results
            completed = 0
            for coro in asyncio.as_completed(tasks):
                result = await coro
                results.append(result)
                completed += 1
                
                if completed % 10 == 0:
                    print(f"  Completed {completed}/{self.config.num_requests} requests")
        
        return results
    
    def calculate_statistics(self, results: List[RequestResult]) -> Dict:
        """Calculate detailed statistics for results."""
        if not results:
            return {}
        
        successful_results = [r for r in results if r.success]
        failed_results = [r for r in results if not r.success]
        
        response_times = [r.response_time for r in successful_results]
        response_sizes = [r.response_size for r in successful_results if r.response_size > 0]
        
        if not response_times:
            return {
                'total_requests': len(results),
                'successful_requests': 0,
                'failed_requests': len(failed_results),
                'success_rate': 0.0,
                'error': 'No successful requests'
            }
        
        # Basic statistics
        stats_dict = {
            'total_requests': len(results),
            'successful_requests': len(successful_results),
            'failed_requests': len(failed_results),
            'success_rate': (len(successful_results) / len(results)) * 100,
            
            # Response time statistics
            'response_time': {
                'mean': statistics.mean(response_times),
                'median': statistics.median(response_times),
                'min': min(response_times),
                'max': max(response_times),
                'std_dev': statistics.stdev(response_times) if len(response_times) > 1 else 0,
                'variance': statistics.variance(response_times) if len(response_times) > 1 else 0
            },
            
            # Percentiles
            'percentiles': {
                'p50': np.percentile(response_times, 50),
                'p75': np.percentile(response_times, 75),
                'p90': np.percentile(response_times, 90),
                'p95': np.percentile(response_times, 95),
                'p99': np.percentile(response_times, 99)
            }
        }
        
        # Response size statistics
        if response_sizes:
            stats_dict['response_size'] = {
                'mean': statistics.mean(response_sizes),
                'median': statistics.median(response_sizes),
                'min': min(response_sizes),
                'max': max(response_sizes)
            }
        
        # Error analysis
        if failed_results:
            error_counts = {}
            for result in failed_results:
                error_key = f"{result.status_code}: {result.error[:50] if result.error else 'HTTP Error'}"
                error_counts[error_key] = error_counts.get(error_key, 0) + 1
            stats_dict['error_distribution'] = error_counts
        
        return stats_dict
    
    def perform_statistical_comparison(self, internet_times: List[float], vpn_times: List[float]) -> Dict:
        """Perform statistical comparison between routing methods."""
        if not internet_times or not vpn_times:
            return {'error': 'Insufficient data for statistical comparison'}
        
        # T-test for means
        t_stat, t_p_value = stats.ttest_ind(internet_times, vpn_times)
        
        # Mann-Whitney U test (non-parametric)
        u_stat, u_p_value = stats.mannwhitneyu(internet_times, vpn_times, alternative='two-sided')
        
        # Kolmogorov-Smirnov test for distribution comparison
        ks_stat, ks_p_value = stats.ks_2samp(internet_times, vpn_times)
        
        # Effect size (Cohen's d)
        pooled_std = np.sqrt(((len(internet_times) - 1) * np.var(internet_times, ddof=1) + 
                             (len(vpn_times) - 1) * np.var(vpn_times, ddof=1)) / 
                            (len(internet_times) + len(vpn_times) - 2))
        cohens_d = (np.mean(internet_times) - np.mean(vpn_times)) / pooled_std if pooled_std > 0 else 0
        
        return {
            'statistical_tests': {
                't_test': {
                    'statistic': t_stat,
                    'p_value': t_p_value,
                    'significant': t_p_value < 0.05,
                    'interpretation': 'Means are significantly different' if t_p_value < 0.05 else 'No significant difference in means'
                },
                'mann_whitney_u': {
                    'statistic': u_stat,
                    'p_value': u_p_value,
                    'significant': u_p_value < 0.05,
                    'interpretation': 'Distributions are significantly different' if u_p_value < 0.05 else 'No significant difference in distributions'
                },
                'kolmogorov_smirnov': {
                    'statistic': ks_stat,
                    'p_value': ks_p_value,
                    'significant': ks_p_value < 0.05,
                    'interpretation': 'Distribution shapes are significantly different' if ks_p_value < 0.05 else 'No significant difference in distribution shapes'
                }
            },
            'effect_size': {
                'cohens_d': cohens_d,
                'interpretation': self._interpret_cohens_d(cohens_d)
            },
            'practical_significance': {
                'mean_difference': np.mean(vpn_times) - np.mean(internet_times),
                'median_difference': np.median(vpn_times) - np.median(internet_times),
                'percentage_difference': ((np.mean(vpn_times) - np.mean(internet_times)) / np.mean(internet_times)) * 100
            }
        }
    
    def _interpret_cohens_d(self, d: float) -> str:
        """Interpret Cohen's d effect size."""
        abs_d = abs(d)
        if abs_d < 0.2:
            return "Negligible effect"
        elif abs_d < 0.5:
            return "Small effect"
        elif abs_d < 0.8:
            return "Medium effect"
        else:
            return "Large effect"
    
    async def run_comparison(self) -> Dict:
        """Run complete performance comparison."""
        print("Starting performance comparison between Internet and VPN routing...")
        print("=" * 60)
        
        start_time = time.time()
        
        # Test Internet routing
        self.internet_results = await self.run_performance_test('/v1/bedrock/invoke-model', 'internet')
        
        # Test VPN routing
        self.vpn_results = await self.run_performance_test('/v1/vpn/bedrock/invoke-model', 'vpn')
        
        total_time = time.time() - start_time
        
        # Calculate statistics
        internet_stats = self.calculate_statistics(self.internet_results)
        vpn_stats = self.calculate_statistics(self.vpn_results)
        
        # Perform statistical comparison if detailed analysis is enabled
        statistical_comparison = {}
        if self.config.detailed_analysis:
            internet_times = [r.response_time for r in self.internet_results if r.success]
            vpn_times = [r.response_time for r in self.vpn_results if r.success]
            
            if internet_times and vpn_times:
                statistical_comparison = self.perform_statistical_comparison(internet_times, vpn_times)
        
        # Generate comparison summary
        comparison_summary = self._generate_comparison_summary(internet_stats, vpn_stats)
        
        return {
            'test_config': {
                'num_requests': self.config.num_requests,
                'concurrent_requests': self.config.concurrent_requests,
                'test_model_id': self.config.test_model_id,
                'detailed_analysis': self.config.detailed_analysis
            },
            'test_duration': total_time,
            'internet_routing': internet_stats,
            'vpn_routing': vpn_stats,
            'statistical_comparison': statistical_comparison,
            'comparison_summary': comparison_summary,
            'timestamp': datetime.utcnow().isoformat()
        }
    
    def _generate_comparison_summary(self, internet_stats: Dict, vpn_stats: Dict) -> Dict:
        """Generate high-level comparison summary."""
        if not internet_stats.get('response_time') or not vpn_stats.get('response_time'):
            return {'error': 'Insufficient data for comparison'}
        
        internet_mean = internet_stats['response_time']['mean']
        vpn_mean = vpn_stats['response_time']['mean']
        
        internet_p95 = internet_stats['percentiles']['p95']
        vpn_p95 = vpn_stats['percentiles']['p95']
        
        internet_success = internet_stats['success_rate']
        vpn_success = vpn_stats['success_rate']
        
        # Determine winner for each metric
        faster_routing = 'internet' if internet_mean < vpn_mean else 'vpn'
        more_reliable_routing = 'internet' if internet_success > vpn_success else 'vpn'
        better_p95_routing = 'internet' if internet_p95 < vpn_p95 else 'vpn'
        
        # Calculate performance differences
        latency_difference = abs(vpn_mean - internet_mean)
        latency_percentage = (latency_difference / min(internet_mean, vpn_mean)) * 100
        
        reliability_difference = abs(vpn_success - internet_success)
        
        return {
            'performance_winner': {
                'faster_routing': faster_routing,
                'more_reliable_routing': more_reliable_routing,
                'better_p95_routing': better_p95_routing
            },
            'differences': {
                'latency_difference_ms': latency_difference,
                'latency_percentage_difference': latency_percentage,
                'reliability_difference_percent': reliability_difference
            },
            'recommendations': self._generate_recommendations(internet_stats, vpn_stats)
        }
    
    def _generate_recommendations(self, internet_stats: Dict, vpn_stats: Dict) -> List[str]:
        """Generate recommendations based on comparison results."""
        recommendations = []
        
        if not internet_stats.get('response_time') or not vpn_stats.get('response_time'):
            return ['Unable to generate recommendations due to insufficient data']
        
        internet_mean = internet_stats['response_time']['mean']
        vpn_mean = vpn_stats['response_time']['mean']
        internet_success = internet_stats['success_rate']
        vpn_success = vpn_stats['success_rate']
        
        # Performance recommendations
        if abs(internet_mean - vpn_mean) / min(internet_mean, vpn_mean) > 0.2:  # >20% difference
            if internet_mean < vpn_mean:
                recommendations.append("Internet routing shows significantly better performance - consider as primary method")
            else:
                recommendations.append("VPN routing shows significantly better performance - investigate network optimizations")
        else:
            recommendations.append("Both routing methods show similar performance - choose based on security requirements")
        
        # Reliability recommendations
        if abs(internet_success - vpn_success) > 5:  # >5% difference
            if internet_success > vpn_success:
                recommendations.append("Internet routing is more reliable - investigate VPN connectivity issues")
            else:
                recommendations.append("VPN routing is more reliable - consider as primary for critical workloads")
        
        # General recommendations
        if internet_stats['response_time']['std_dev'] > vpn_stats['response_time']['std_dev'] * 1.5:
            recommendations.append("Internet routing shows high variability - implement retry logic")
        elif vpn_stats['response_time']['std_dev'] > internet_stats['response_time']['std_dev'] * 1.5:
            recommendations.append("VPN routing shows high variability - optimize VPN configuration")
        
        return recommendations

async def main():
    parser = argparse.ArgumentParser(description="Performance comparison script")
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--num-requests", type=int, default=100)
    parser.add_argument("--concurrent-requests", type=int, default=10)
    parser.add_argument("--test-model-id", default="anthropic.claude-3-haiku-20240307-v1:0")
    parser.add_argument("--detailed-analysis", action="store_true", default=True)
    parser.add_argument("--output-file", required=True)
    
    args = parser.parse_args()
    
    config = PerfTestConfig(
        api_url=args.api_url,
        api_key=args.api_key,
        num_requests=args.num_requests,
        concurrent_requests=args.concurrent_requests,
        test_model_id=args.test_model_id,
        detailed_analysis=args.detailed_analysis
    )
    
    comparator = PerformanceComparator(config)
    results = await comparator.run_comparison()
    
    # Save results
    with open(args.output_file, 'w') as f:
        json.dump(results, f, indent=2, default=str)
    
    # Print summary
    print("\n" + "="*60)
    print("PERFORMANCE COMPARISON SUMMARY")
    print("="*60)
    
    if 'internet_routing' in results and 'vpn_routing' in results:
        internet = results['internet_routing']
        vpn = results['vpn_routing']
        
        print(f"\nInternet Routing:")
        print(f"  Success Rate: {internet.get('success_rate', 0):.1f}%")
        if 'response_time' in internet:
            print(f"  Mean Response Time: {internet['response_time']['mean']:.0f}ms")
            print(f"  P95 Response Time: {internet['percentiles']['p95']:.0f}ms")
        
        print(f"\nVPN Routing:")
        print(f"  Success Rate: {vpn.get('success_rate', 0):.1f}%")
        if 'response_time' in vpn:
            print(f"  Mean Response Time: {vpn['response_time']['mean']:.0f}ms")
            print(f"  P95 Response Time: {vpn['percentiles']['p95']:.0f}ms")
        
        if 'comparison_summary' in results and 'recommendations' in results['comparison_summary']:
            print(f"\nRecommendations:")
            for rec in results['comparison_summary']['recommendations']:
                print(f"  • {rec}")
    
    print("="*60)

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Make the performance comparison script executable
chmod +x "$PERF_COMP_SCRIPT"

# Check Python dependencies for performance comparison
log_info "Checking Python dependencies for performance comparison..."

PYTHON_CMD="python3"
REQUIRED_PACKAGES=("aiohttp" "scipy" "numpy")
MISSING_PACKAGES=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! $PYTHON_CMD -c "import $package" 2>/dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    log_warning "Missing Python packages for performance comparison: ${MISSING_PACKAGES[*]}"
    log_info "Installing missing packages..."
    $PYTHON_CMD -m pip install "${MISSING_PACKAGES[@]}"
fi

# Run the performance comparison
PERF_COMP_OUTPUT="$PROJECT_ROOT/$OUTPUT_DIR/performance_comparison_${TIMESTAMP}.json"
PERF_COMP_REPORT="$PROJECT_ROOT/$OUTPUT_DIR/performance_comparison_report_${TIMESTAMP}.md"

log_info ""
log_info "Starting performance comparison execution..."

# Build Python command arguments
PYTHON_ARGS=(
    --api-url "$API_GATEWAY_URL"
    --api-key "$API_KEY"
    --num-requests "$NUM_REQUESTS"
    --concurrent-requests "$CONCURRENT_REQUESTS"
    --test-model-id "$TEST_MODEL_ID"
    --output-file "$PERF_COMP_OUTPUT"
)

if [[ "$DETAILED_ANALYSIS" == "true" ]]; then
    PYTHON_ARGS+=(--detailed-analysis)
fi

# Run the performance comparison
if $PYTHON_CMD "$PERF_COMP_SCRIPT" "${PYTHON_ARGS[@]}"; then
    log_success "Performance comparison completed successfully"
    PERF_COMP_SUCCESS="true"
else
    log_error "Performance comparison failed"
    PERF_COMP_SUCCESS="false"
fi

# Generate performance comparison report
log_info "Generating performance comparison report..."

cat > "$PERF_COMP_REPORT" << EOF
# Performance Comparison Report

## Test Configuration
- **Test Run ID**: $TEST_RUN_ID
- **Project**: $PROJECT_NAME
- **Environment**: $ENVIRONMENT
- **API Gateway URL**: $API_GATEWAY_URL
- **Test Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Test Parameters
- **Requests per Method**: $NUM_REQUESTS
- **Concurrent Requests**: $CONCURRENT_REQUESTS
- **Test Model**: $TEST_MODEL_ID
- **Detailed Analysis**: $DETAILED_ANALYSIS

## Test Results

### Overall Status
$(if [[ "$PERF_COMP_SUCCESS" == "true" ]]; then
    echo "✅ **PASSED** - Performance comparison completed successfully"
else
    echo "❌ **FAILED** - Performance comparison encountered errors"
fi)

### Performance Metrics Comparison

$(if [[ -f "$PERF_COMP_OUTPUT" ]] && command -v jq &> /dev/null; then
    echo "#### Internet Routing Performance"
    echo ""
    INT_SUCCESS_RATE=$(jq -r '.internet_routing.success_rate // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    INT_MEAN_TIME=$(jq -r '.internet_routing.response_time.mean // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    INT_P95_TIME=$(jq -r '.internet_routing.percentiles.p95 // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    INT_P99_TIME=$(jq -r '.internet_routing.percentiles.p99 // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    INT_STD_DEV=$(jq -r '.internet_routing.response_time.std_dev // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    
    echo "- **Success Rate**: ${INT_SUCCESS_RATE}%"
    echo "- **Mean Response Time**: ${INT_MEAN_TIME}ms"
    echo "- **P95 Response Time**: ${INT_P95_TIME}ms"
    echo "- **P99 Response Time**: ${INT_P99_TIME}ms"
    echo "- **Standard Deviation**: ${INT_STD_DEV}ms"
    echo ""
    
    echo "#### VPN Routing Performance"
    echo ""
    VPN_SUCCESS_RATE=$(jq -r '.vpn_routing.success_rate // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    VPN_MEAN_TIME=$(jq -r '.vpn_routing.response_time.mean // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    VPN_P95_TIME=$(jq -r '.vpn_routing.percentiles.p95 // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    VPN_P99_TIME=$(jq -r '.vpn_routing.percentiles.p99 // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    VPN_STD_DEV=$(jq -r '.vpn_routing.response_time.std_dev // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    
    echo "- **Success Rate**: ${VPN_SUCCESS_RATE}%"
    echo "- **Mean Response Time**: ${VPN_MEAN_TIME}ms"
    echo "- **P95 Response Time**: ${VPN_P95_TIME}ms"
    echo "- **P99 Response Time**: ${VPN_P99_TIME}ms"
    echo "- **Standard Deviation**: ${VPN_STD_DEV}ms"
    echo ""
    
    echo "#### Performance Comparison Summary"
    echo ""
    FASTER_ROUTING=$(jq -r '.comparison_summary.performance_winner.faster_routing // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    MORE_RELIABLE=$(jq -r '.comparison_summary.performance_winner.more_reliable_routing // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    LATENCY_DIFF=$(jq -r '.comparison_summary.differences.latency_difference_ms // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    LATENCY_PERCENT=$(jq -r '.comparison_summary.differences.latency_percentage_difference // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    
    echo "- **Faster Routing Method**: $FASTER_ROUTING"
    echo "- **More Reliable Method**: $MORE_RELIABLE"
    echo "- **Latency Difference**: ${LATENCY_DIFF}ms (${LATENCY_PERCENT}%)"
    echo ""
    
    if [[ "$DETAILED_ANALYSIS" == "true" ]]; then
        echo "#### Statistical Analysis"
        echo ""
        T_TEST_SIG=$(jq -r '.statistical_comparison.statistical_tests.t_test.significant // false' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "false")
        T_TEST_INTERP=$(jq -r '.statistical_comparison.statistical_tests.t_test.interpretation // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
        COHENS_D=$(jq -r '.statistical_comparison.effect_size.cohens_d // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
        EFFECT_INTERP=$(jq -r '.statistical_comparison.effect_size.interpretation // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
        
        echo "- **Statistical Significance**: $(if [[ "$T_TEST_SIG" == "true" ]]; then echo "Yes"; else echo "No"; fi)"
        echo "- **T-test Result**: $T_TEST_INTERP"
        echo "- **Effect Size (Cohen's d)**: $COHENS_D"
        echo "- **Effect Size Interpretation**: $EFFECT_INTERP"
        echo ""
    fi
else
    echo "Detailed performance metrics are available in the JSON output file."
fi)

## Recommendations

$(if [[ -f "$PERF_COMP_OUTPUT" ]] && command -v jq &> /dev/null; then
    echo "### Performance Optimization Recommendations"
    echo ""
    jq -r '.comparison_summary.recommendations[]? // empty' "$PERF_COMP_OUTPUT" 2>/dev/null | while read -r rec; do
        echo "- $rec"
    done
    echo ""
fi)

### General Recommendations

1. **Routing Strategy**:
   - Use performance comparison results to inform routing decisions
   - Consider implementing intelligent routing based on performance metrics

2. **Monitoring**:
   - Set up continuous performance monitoring
   - Configure alerts based on performance thresholds observed

3. **Optimization**:
   - Investigate and optimize the slower routing method
   - Consider caching strategies for frequently accessed models

4. **Capacity Planning**:
   - Use performance data for capacity planning
   - Plan for peak load scenarios based on test results

## Detailed Results

Full performance comparison results are available in: \`$PERF_COMP_OUTPUT\`

## Next Steps

1. **Analyze Results**: Review detailed JSON results for insights
2. **Optimize Performance**: Address performance gaps between routing methods
3. **Implement Monitoring**: Set up ongoing performance monitoring
4. **Regular Testing**: Schedule regular performance comparisons
5. **Documentation**: Update operational documentation with findings

---
*Report generated by performance comparison script*
*Test Run ID: $TEST_RUN_ID*
EOF

# Clean up temporary script
rm -f "$PERF_COMP_SCRIPT"

# Display results
log_info ""
log_info "Performance Comparison Summary:"
log_info "=============================="

if [[ "$PERF_COMP_SUCCESS" == "true" ]]; then
    log_success "✅ Performance comparison PASSED"
else
    log_error "❌ Performance comparison FAILED"
fi

log_info ""
log_info "Generated Reports:"
log_info "  📊 Detailed Results: $PERF_COMP_OUTPUT"
log_info "  📋 Comparison Report: $PERF_COMP_REPORT"

# Display key metrics if available
if [[ -f "$PERF_COMP_OUTPUT" ]] && command -v jq &> /dev/null; then
    log_info ""
    log_info "Quick Performance Summary:"
    
    INT_SUCCESS_RATE=$(jq -r '.internet_routing.success_rate // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    VPN_SUCCESS_RATE=$(jq -r '.vpn_routing.success_rate // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    INT_MEAN_TIME=$(jq -r '.internet_routing.response_time.mean // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    VPN_MEAN_TIME=$(jq -r '.vpn_routing.response_time.mean // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    FASTER_ROUTING=$(jq -r '.comparison_summary.performance_winner.faster_routing // "N/A"' "$PERF_COMP_OUTPUT" 2>/dev/null || echo "N/A")
    
    if [[ "$INT_SUCCESS_RATE" != "N/A" ]]; then
        log_info "  🌐 Internet Success Rate: ${INT_SUCCESS_RATE}%"
    fi
    if [[ "$VPN_SUCCESS_RATE" != "N/A" ]]; then
        log_info "  🔒 VPN Success Rate: ${VPN_SUCCESS_RATE}%"
    fi
    if [[ "$INT_MEAN_TIME" != "N/A" ]]; then
        log_info "  ⚡ Internet Mean Time: ${INT_MEAN_TIME}ms"
    fi
    if [[ "$VPN_MEAN_TIME" != "N/A" ]]; then
        log_info "  🔐 VPN Mean Time: ${VPN_MEAN_TIME}ms"
    fi
    if [[ "$FASTER_ROUTING" != "N/A" ]]; then
        log_info "  🏆 Faster Method: $FASTER_ROUTING"
    fi
fi

log_info ""
log_info "Next Steps:"
log_info "1. Review the detailed comparison report: $PERF_COMP_REPORT"
log_info "2. Analyze performance metrics in: $PERF_COMP_OUTPUT"
log_info "3. Implement optimizations based on comparison results"
log_info "4. Set up ongoing performance monitoring"

# Exit with appropriate code
if [[ "$PERF_COMP_SUCCESS" == "true" ]]; then
    exit 0
else
    exit 1
fi