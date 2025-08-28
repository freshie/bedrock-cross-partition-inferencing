#!/bin/bash

# Advanced load testing script for dual routing system
# This script provides comprehensive load testing capabilities

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
API_GATEWAY_STACK=""
TEST_MODEL_ID="anthropic.claude-3-haiku-20240307-v1:0"
ROUTING_METHOD="both"
DURATION="300"
RPS="10"
MAX_RPS="50"
RAMP_UP_TIME="60"
CONCURRENT_USERS="20"
OUTPUT_DIR="outputs"
STRESS_TEST="false"
SPIKE_TEST="false"

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
Advanced load testing script for dual routing system

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --api-gateway-stack NAME    API Gateway CloudFormation stack name (required)
    --test-model-id ID          Model ID for testing (default: anthropic.claude-3-haiku-20240307-v1:0)
    --routing-method METHOD     Routing method to test: internet, vpn, both (default: both)
    --duration SEC              Test duration in seconds (default: 300)
    --rps NUM                   Target requests per second (default: 10)
    --max-rps NUM               Maximum RPS for stress testing (default: 50)
    --ramp-up-time SEC          Ramp-up time in seconds (default: 60)
    --concurrent-users NUM      Number of concurrent users (default: 20)
    --output-dir DIR            Output directory for reports (default: outputs)
    --stress-test               Run stress test (gradually increase load)
    --spike-test                Run spike test (sudden load increases)
    --help                     Show this help message

Test Types:
    - Load Test: Sustained load at target RPS
    - Stress Test: Gradually increase load to find breaking point
    - Spike Test: Sudden load spikes to test elasticity

Examples:
    # Basic load test
    $0 --api-gateway-stack my-api-gateway-stack \\
       --duration 300 --rps 20

    # Stress test to find limits
    $0 --api-gateway-stack my-api-gateway-stack \\
       --stress-test --max-rps 100

    # Spike test for elasticity
    $0 --api-gateway-stack my-api-gateway-stack \\
       --spike-test --max-rps 50

    # VPN-only load test
    $0 --api-gateway-stack my-api-gateway-stack \\
       --routing-method vpn --duration 600

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
        --routing-method)
            ROUTING_METHOD="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --rps)
            RPS="$2"
            shift 2
            ;;
        --max-rps)
            MAX_RPS="$2"
            shift 2
            ;;
        --ramp-up-time)
            RAMP_UP_TIME="$2"
            shift 2
            ;;
        --concurrent-users)
            CONCURRENT_USERS="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --stress-test)
            STRESS_TEST="true"
            shift
            ;;
        --spike-test)
            SPIKE_TEST="true"
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

# Validate routing method
if [[ "$ROUTING_METHOD" != "internet" && "$ROUTING_METHOD" != "vpn" && "$ROUTING_METHOD" != "both" ]]; then
    log_error "Invalid routing method: $ROUTING_METHOD. Must be 'internet', 'vpn', or 'both'."
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

log_info "Starting advanced load testing for dual routing system..."
log_info "  Project: $PROJECT_NAME"
log_info "  Environment: $ENVIRONMENT"
log_info "  Region: $AWS_REGION"
log_info "  API Gateway Stack: $API_GATEWAY_STACK"
log_info "  Routing Method: $ROUTING_METHOD"
log_info "  Test Duration: ${DURATION}s"
log_info "  Target RPS: $RPS"
log_info "  Stress Test: $STRESS_TEST"
log_info "  Spike Test: $SPIKE_TEST"

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
TEST_RUN_ID="${PROJECT_NAME}_${ENVIRONMENT}_loadtest_${TIMESTAMP}"

# Create load testing Python script
LOAD_TEST_SCRIPT="$PROJECT_ROOT/$OUTPUT_DIR/load_test_${TIMESTAMP}.py"

cat > "$LOAD_TEST_SCRIPT" << 'EOF'
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

@dataclass
class LoadTestConfig:
    api_url: str
    api_key: str
    routing_method: str
    duration: int
    rps: int
    max_rps: int
    ramp_up_time: int
    concurrent_users: int
    test_model_id: str
    stress_test: bool = False
    spike_test: bool = False

@dataclass
class RequestResult:
    timestamp: float
    success: bool
    status_code: int
    response_time: float
    routing_method: str
    error: str = None

class LoadTester:
    def __init__(self, config: LoadTestConfig):
        self.config = config
        self.results: List[RequestResult] = []
        self.start_time = None
        
    async def make_request(self, session: aiohttp.ClientSession, path: str, routing_method: str) -> RequestResult:
        """Make a single HTTP request."""
        url = f"{self.config.api_url}{path}"
        
        payload = {
            "modelId": self.config.test_model_id,
            "body": {
                "messages": [
                    {
                        "role": "user",
                        "content": f"Load test message {int(time.time())}. Brief response please."
                    }
                ],
                "max_tokens": 20,
                "temperature": 0.3
            }
        }
        
        headers = {
            'X-API-Key': self.config.api_key,
            'Content-Type': 'application/json'
        }
        
        start_time = time.time()
        
        try:
            async with session.post(url, json=payload, headers=headers, timeout=30) as response:
                response_time = (time.time() - start_time) * 1000
                
                return RequestResult(
                    timestamp=start_time,
                    success=response.status < 400,
                    status_code=response.status,
                    response_time=response_time,
                    routing_method=routing_method
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
    
    async def run_load_test(self) -> Dict:
        """Run the load test."""
        print(f"Starting load test...")
        print(f"  Duration: {self.config.duration}s")
        print(f"  Target RPS: {self.config.rps}")
        print(f"  Routing: {self.config.routing_method}")
        
        self.start_time = time.time()
        
        # Determine paths to test
        paths = []
        if self.config.routing_method in ['internet', 'both']:
            paths.append(('/v1/bedrock/invoke-model', 'internet'))
        if self.config.routing_method in ['vpn', 'both']:
            paths.append(('/v1/vpn/bedrock/invoke-model', 'vpn'))
        
        # Create session
        connector = aiohttp.TCPConnector(limit=self.config.concurrent_users * 2)
        timeout = aiohttp.ClientTimeout(total=30)
        
        async with aiohttp.ClientSession(connector=connector, timeout=timeout) as session:
            if self.config.stress_test:
                await self._run_stress_test(session, paths)
            elif self.config.spike_test:
                await self._run_spike_test(session, paths)
            else:
                await self._run_sustained_load_test(session, paths)
        
        return self._generate_report()
    
    async def _run_sustained_load_test(self, session: aiohttp.ClientSession, paths: List[Tuple[str, str]]):
        """Run sustained load test."""
        print("Running sustained load test...")
        
        request_interval = 1.0 / self.config.rps
        end_time = self.start_time + self.config.duration
        
        tasks = []
        
        while time.time() < end_time:
            for path, routing_method in paths:
                if time.time() >= end_time:
                    break
                
                task = asyncio.create_task(self.make_request(session, path, routing_method))
                tasks.append(task)
                
                await asyncio.sleep(request_interval / len(paths))
        
        # Wait for all tasks to complete
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        for result in results:
            if isinstance(result, RequestResult):
                self.results.append(result)
    
    async def _run_stress_test(self, session: aiohttp.ClientSession, paths: List[Tuple[str, str]]):
        """Run stress test with gradually increasing load."""
        print("Running stress test...")
        
        current_rps = 1
        step_duration = 30  # 30 seconds per step
        rps_increment = max(1, (self.config.max_rps - 1) // (self.config.duration // step_duration))
        
        end_time = self.start_time + self.config.duration
        
        while time.time() < end_time and current_rps <= self.config.max_rps:
            step_end_time = min(time.time() + step_duration, end_time)
            print(f"  Testing at {current_rps} RPS...")
            
            request_interval = 1.0 / current_rps
            tasks = []
            
            while time.time() < step_end_time:
                for path, routing_method in paths:
                    if time.time() >= step_end_time:
                        break
                    
                    task = asyncio.create_task(self.make_request(session, path, routing_method))
                    tasks.append(task)
                    
                    await asyncio.sleep(request_interval / len(paths))
            
            # Wait for step tasks to complete
            step_results = await asyncio.gather(*tasks, return_exceptions=True)
            
            for result in step_results:
                if isinstance(result, RequestResult):
                    self.results.append(result)
            
            current_rps += rps_increment
    
    async def _run_spike_test(self, session: aiohttp.ClientSession, paths: List[Tuple[str, str]]):
        """Run spike test with sudden load increases."""
        print("Running spike test...")
        
        # Normal load phase
        normal_duration = self.config.duration // 3
        spike_duration = self.config.duration // 6
        
        phases = [
            (self.config.rps, normal_duration, "Normal Load"),
            (self.config.max_rps, spike_duration, "Spike Load"),
            (self.config.rps, normal_duration, "Recovery"),
            (self.config.max_rps, spike_duration, "Second Spike"),
            (self.config.rps, self.config.duration - (2 * normal_duration + 2 * spike_duration), "Final Recovery")
        ]
        
        for rps, duration, phase_name in phases:
            if duration <= 0:
                continue
                
            print(f"  {phase_name}: {rps} RPS for {duration}s")
            phase_end_time = time.time() + duration
            request_interval = 1.0 / rps
            tasks = []
            
            while time.time() < phase_end_time:
                for path, routing_method in paths:
                    if time.time() >= phase_end_time:
                        break
                    
                    task = asyncio.create_task(self.make_request(session, path, routing_method))
                    tasks.append(task)
                    
                    await asyncio.sleep(request_interval / len(paths))
            
            # Wait for phase tasks to complete
            phase_results = await asyncio.gather(*tasks, return_exceptions=True)
            
            for result in phase_results:
                if isinstance(result, RequestResult):
                    self.results.append(result)
    
    def _generate_report(self) -> Dict:
        """Generate test report."""
        if not self.results:
            return {"error": "No results collected"}
        
        total_duration = time.time() - self.start_time
        
        # Overall metrics
        total_requests = len(self.results)
        successful_requests = sum(1 for r in self.results if r.success)
        failed_requests = total_requests - successful_requests
        success_rate = (successful_requests / total_requests) * 100 if total_requests > 0 else 0
        
        # Response time metrics
        response_times = [r.response_time for r in self.results]
        avg_response_time = statistics.mean(response_times) if response_times else 0
        min_response_time = min(response_times) if response_times else 0
        max_response_time = max(response_times) if response_times else 0
        
        sorted_times = sorted(response_times)
        p50 = sorted_times[int(0.5 * len(sorted_times))] if sorted_times else 0
        p95 = sorted_times[int(0.95 * len(sorted_times))] if sorted_times else 0
        p99 = sorted_times[int(0.99 * len(sorted_times))] if sorted_times else 0
        
        # Throughput
        actual_rps = total_requests / total_duration if total_duration > 0 else 0
        
        # Error analysis
        error_distribution = {}
        for result in self.results:
            if not result.success:
                error_key = f"{result.status_code}: {result.error[:50] if result.error else 'HTTP Error'}"
                error_distribution[error_key] = error_distribution.get(error_key, 0) + 1
        
        # Per-routing-method breakdown
        routing_breakdown = {}
        for routing_method in ['internet', 'vpn']:
            method_results = [r for r in self.results if r.routing_method == routing_method]
            if method_results:
                method_successful = sum(1 for r in method_results if r.success)
                method_times = [r.response_time for r in method_results]
                
                routing_breakdown[routing_method] = {
                    'total_requests': len(method_results),
                    'successful_requests': method_successful,
                    'success_rate': (method_successful / len(method_results)) * 100,
                    'avg_response_time': statistics.mean(method_times) if method_times else 0,
                    'p95_response_time': sorted(method_times)[int(0.95 * len(method_times))] if method_times else 0
                }
        
        return {
            'test_config': {
                'duration': self.config.duration,
                'target_rps': self.config.rps,
                'routing_method': self.config.routing_method,
                'stress_test': self.config.stress_test,
                'spike_test': self.config.spike_test
            },
            'overall_metrics': {
                'total_duration': total_duration,
                'total_requests': total_requests,
                'successful_requests': successful_requests,
                'failed_requests': failed_requests,
                'success_rate': success_rate,
                'actual_rps': actual_rps,
                'avg_response_time': avg_response_time,
                'min_response_time': min_response_time,
                'max_response_time': max_response_time,
                'p50_response_time': p50,
                'p95_response_time': p95,
                'p99_response_time': p99
            },
            'routing_breakdown': routing_breakdown,
            'error_distribution': error_distribution,
            'timestamp': datetime.utcnow().isoformat()
        }

async def main():
    parser = argparse.ArgumentParser(description="Load testing script")
    parser.add_argument("--api-url", required=True)
    parser.add_argument("--api-key", required=True)
    parser.add_argument("--routing-method", default="both")
    parser.add_argument("--duration", type=int, default=300)
    parser.add_argument("--rps", type=int, default=10)
    parser.add_argument("--max-rps", type=int, default=50)
    parser.add_argument("--concurrent-users", type=int, default=20)
    parser.add_argument("--test-model-id", default="anthropic.claude-3-haiku-20240307-v1:0")
    parser.add_argument("--stress-test", action="store_true")
    parser.add_argument("--spike-test", action="store_true")
    parser.add_argument("--output-file", required=True)
    
    args = parser.parse_args()
    
    config = LoadTestConfig(
        api_url=args.api_url,
        api_key=args.api_key,
        routing_method=args.routing_method,
        duration=args.duration,
        rps=args.rps,
        max_rps=args.max_rps,
        concurrent_users=args.concurrent_users,
        test_model_id=args.test_model_id,
        stress_test=args.stress_test,
        spike_test=args.spike_test
    )
    
    tester = LoadTester(config)
    results = await tester.run_load_test()
    
    # Save results
    with open(args.output_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    # Print summary
    print("\n" + "="*60)
    print("LOAD TEST SUMMARY")
    print("="*60)
    
    if 'overall_metrics' in results:
        metrics = results['overall_metrics']
        print(f"Total Requests: {metrics['total_requests']}")
        print(f"Success Rate: {metrics['success_rate']:.1f}%")
        print(f"Actual RPS: {metrics['actual_rps']:.1f}")
        print(f"Avg Response Time: {metrics['avg_response_time']:.0f}ms")
        print(f"P95 Response Time: {metrics['p95_response_time']:.0f}ms")
        print(f"P99 Response Time: {metrics['p99_response_time']:.0f}ms")
        
        if results.get('routing_breakdown'):
            print("\nPer-Routing Method:")
            for method, breakdown in results['routing_breakdown'].items():
                print(f"  {method.upper()}:")
                print(f"    Success Rate: {breakdown['success_rate']:.1f}%")
                print(f"    Avg Response Time: {breakdown['avg_response_time']:.0f}ms")
    
    print("="*60)

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Make the load test script executable
chmod +x "$LOAD_TEST_SCRIPT"

# Check Python dependencies for load testing
log_info "Checking Python dependencies for load testing..."

PYTHON_CMD="python3"
REQUIRED_PACKAGES=("aiohttp")
MISSING_PACKAGES=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! $PYTHON_CMD -c "import $package" 2>/dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    log_warning "Missing Python packages for load testing: ${MISSING_PACKAGES[*]}"
    log_info "Installing missing packages..."
    $PYTHON_CMD -m pip install "${MISSING_PACKAGES[@]}"
fi

# Run the load test
LOAD_TEST_OUTPUT="$PROJECT_ROOT/$OUTPUT_DIR/load_test_results_${TIMESTAMP}.json"
LOAD_TEST_REPORT="$PROJECT_ROOT/$OUTPUT_DIR/load_test_report_${TIMESTAMP}.md"

log_info ""
log_info "Starting load test execution..."

# Build Python command arguments
PYTHON_ARGS=(
    --api-url "$API_GATEWAY_URL"
    --api-key "$API_KEY"
    --routing-method "$ROUTING_METHOD"
    --duration "$DURATION"
    --rps "$RPS"
    --max-rps "$MAX_RPS"
    --concurrent-users "$CONCURRENT_USERS"
    --test-model-id "$TEST_MODEL_ID"
    --output-file "$LOAD_TEST_OUTPUT"
)

if [[ "$STRESS_TEST" == "true" ]]; then
    PYTHON_ARGS+=(--stress-test)
fi

if [[ "$SPIKE_TEST" == "true" ]]; then
    PYTHON_ARGS+=(--spike-test)
fi

# Run the load test
if $PYTHON_CMD "$LOAD_TEST_SCRIPT" "${PYTHON_ARGS[@]}"; then
    log_success "Load test completed successfully"
    LOAD_TEST_SUCCESS="true"
else
    log_error "Load test failed"
    LOAD_TEST_SUCCESS="false"
fi

# Generate load test report
log_info "Generating load test report..."

cat > "$LOAD_TEST_REPORT" << EOF
# Load Test Report

## Test Configuration
- **Test Run ID**: $TEST_RUN_ID
- **Project**: $PROJECT_NAME
- **Environment**: $ENVIRONMENT
- **API Gateway URL**: $API_GATEWAY_URL
- **Test Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Load Test Parameters
- **Routing Method**: $ROUTING_METHOD
- **Test Duration**: ${DURATION} seconds
- **Target RPS**: $RPS
- **Max RPS**: $MAX_RPS (for stress/spike tests)
- **Concurrent Users**: $CONCURRENT_USERS
- **Test Model**: $TEST_MODEL_ID
- **Stress Test**: $STRESS_TEST
- **Spike Test**: $SPIKE_TEST

## Test Results

### Overall Status
$(if [[ "$LOAD_TEST_SUCCESS" == "true" ]]; then
    echo "✅ **PASSED** - Load test completed successfully"
else
    echo "❌ **FAILED** - Load test encountered errors"
fi)

### Performance Metrics

$(if [[ -f "$LOAD_TEST_OUTPUT" ]] && command -v jq &> /dev/null; then
    echo "#### Overall Performance"
    echo ""
    TOTAL_REQUESTS=$(jq -r '.overall_metrics.total_requests // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    SUCCESS_RATE=$(jq -r '.overall_metrics.success_rate // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    ACTUAL_RPS=$(jq -r '.overall_metrics.actual_rps // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    AVG_RESPONSE_TIME=$(jq -r '.overall_metrics.avg_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    P95_RESPONSE_TIME=$(jq -r '.overall_metrics.p95_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    P99_RESPONSE_TIME=$(jq -r '.overall_metrics.p99_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    
    echo "- **Total Requests**: $TOTAL_REQUESTS"
    echo "- **Success Rate**: ${SUCCESS_RATE}%"
    echo "- **Actual RPS**: $ACTUAL_RPS"
    echo "- **Average Response Time**: ${AVG_RESPONSE_TIME}ms"
    echo "- **P95 Response Time**: ${P95_RESPONSE_TIME}ms"
    echo "- **P99 Response Time**: ${P99_RESPONSE_TIME}ms"
    echo ""
    
    # Check if routing breakdown exists
    if jq -e '.routing_breakdown.internet' "$LOAD_TEST_OUTPUT" >/dev/null 2>&1; then
        echo "#### Internet Routing Performance"
        echo ""
        INT_SUCCESS_RATE=$(jq -r '.routing_breakdown.internet.success_rate // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
        INT_AVG_TIME=$(jq -r '.routing_breakdown.internet.avg_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
        INT_P95_TIME=$(jq -r '.routing_breakdown.internet.p95_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
        
        echo "- **Success Rate**: ${INT_SUCCESS_RATE}%"
        echo "- **Average Response Time**: ${INT_AVG_TIME}ms"
        echo "- **P95 Response Time**: ${INT_P95_TIME}ms"
        echo ""
    fi
    
    if jq -e '.routing_breakdown.vpn' "$LOAD_TEST_OUTPUT" >/dev/null 2>&1; then
        echo "#### VPN Routing Performance"
        echo ""
        VPN_SUCCESS_RATE=$(jq -r '.routing_breakdown.vpn.success_rate // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
        VPN_AVG_TIME=$(jq -r '.routing_breakdown.vpn.avg_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
        VPN_P95_TIME=$(jq -r '.routing_breakdown.vpn.p95_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
        
        echo "- **Success Rate**: ${VPN_SUCCESS_RATE}%"
        echo "- **Average Response Time**: ${VPN_AVG_TIME}ms"
        echo "- **P95 Response Time**: ${VPN_P95_TIME}ms"
        echo ""
    fi
else
    echo "Detailed performance metrics are available in the JSON output file."
fi)

## Test Analysis

### Performance Assessment
$(if [[ -f "$LOAD_TEST_OUTPUT" ]] && command -v jq &> /dev/null; then
    SUCCESS_RATE=$(jq -r '.overall_metrics.success_rate // 0' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "0")
    P95_TIME=$(jq -r '.overall_metrics.p95_response_time // 0' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "0")
    
    if (( $(echo "$SUCCESS_RATE >= 99" | bc -l) )); then
        echo "✅ **Excellent** - Success rate above 99%"
    elif (( $(echo "$SUCCESS_RATE >= 95" | bc -l) )); then
        echo "⚠️ **Good** - Success rate above 95%"
    else
        echo "❌ **Poor** - Success rate below 95%"
    fi
    
    if (( $(echo "$P95_TIME <= 5000" | bc -l) )); then
        echo "✅ **Excellent** - P95 response time under 5 seconds"
    elif (( $(echo "$P95_TIME <= 10000" | bc -l) )); then
        echo "⚠️ **Acceptable** - P95 response time under 10 seconds"
    else
        echo "❌ **Poor** - P95 response time over 10 seconds"
    fi
fi)

### Recommendations

1. **Capacity Planning**:
   - Use actual RPS results for capacity planning
   - Consider peak load scenarios based on test results

2. **Performance Optimization**:
   - Investigate any high response times
   - Optimize based on routing method performance differences

3. **Scaling Strategy**:
   - Set up auto-scaling based on load test insights
   - Configure appropriate Lambda concurrency limits

4. **Monitoring**:
   - Set up alerts based on performance thresholds observed
   - Monitor key metrics identified during load testing

## Detailed Results

Full test results are available in: \`$LOAD_TEST_OUTPUT\`

## Next Steps

1. **Review Results**: Analyze detailed JSON results for insights
2. **Optimize Performance**: Address any performance bottlenecks
3. **Scale Infrastructure**: Adjust capacity based on load test findings
4. **Set Monitoring**: Configure alerts based on observed thresholds
5. **Regular Testing**: Schedule regular load tests to track performance

---
*Report generated by load testing script*
*Test Run ID: $TEST_RUN_ID*
EOF

# Clean up temporary script
rm -f "$LOAD_TEST_SCRIPT"

# Display results
log_info ""
log_info "Load Test Summary:"
log_info "=================="

if [[ "$LOAD_TEST_SUCCESS" == "true" ]]; then
    log_success "✅ Load test PASSED"
else
    log_error "❌ Load test FAILED"
fi

log_info ""
log_info "Generated Reports:"
log_info "  📊 Detailed Results: $LOAD_TEST_OUTPUT"
log_info "  📋 Load Test Report: $LOAD_TEST_REPORT"

# Display key metrics if available
if [[ -f "$LOAD_TEST_OUTPUT" ]] && command -v jq &> /dev/null; then
    log_info ""
    log_info "Quick Performance Summary:"
    
    TOTAL_REQUESTS=$(jq -r '.overall_metrics.total_requests // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    SUCCESS_RATE=$(jq -r '.overall_metrics.success_rate // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    ACTUAL_RPS=$(jq -r '.overall_metrics.actual_rps // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    AVG_RESPONSE_TIME=$(jq -r '.overall_metrics.avg_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    P95_RESPONSE_TIME=$(jq -r '.overall_metrics.p95_response_time // "N/A"' "$LOAD_TEST_OUTPUT" 2>/dev/null || echo "N/A")
    
    if [[ "$TOTAL_REQUESTS" != "N/A" ]]; then
        log_info "  📈 Total Requests: $TOTAL_REQUESTS"
    fi
    if [[ "$SUCCESS_RATE" != "N/A" ]]; then
        log_info "  ✅ Success Rate: ${SUCCESS_RATE}%"
    fi
    if [[ "$ACTUAL_RPS" != "N/A" ]]; then
        log_info "  ⚡ Actual RPS: $ACTUAL_RPS"
    fi
    if [[ "$AVG_RESPONSE_TIME" != "N/A" ]]; then
        log_info "  ⏱️  Avg Response Time: ${AVG_RESPONSE_TIME}ms"
    fi
    if [[ "$P95_RESPONSE_TIME" != "N/A" ]]; then
        log_info "  📊 P95 Response Time: ${P95_RESPONSE_TIME}ms"
    fi
fi

log_info ""
log_info "Next Steps:"
log_info "1. Review the detailed load test report: $LOAD_TEST_REPORT"
log_info "2. Analyze performance metrics in: $LOAD_TEST_OUTPUT"
log_info "3. Optimize system based on load test findings"
log_info "4. Set up monitoring and alerting based on observed thresholds"

# Exit with appropriate code
if [[ "$LOAD_TEST_SUCCESS" == "true" ]]; then
    exit 0
else
    exit 1
fi