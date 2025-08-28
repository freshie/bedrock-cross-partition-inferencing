# Cross-Partition Routing Tests

This directory contains comprehensive test suites for both internet and VPN routing methods used in the cross-partition AI inference solution.

## Test Files

### `test_internet_routing.py`
Tests the original internet-based routing approach via API Gateway.

**Features:**
- API Gateway endpoint availability testing
- Bedrock inference via internet routing
- Authentication mechanism validation
- Audit trail verification
- Performance baseline establishment

**Usage:**
```bash
python3 tests/test_internet_routing.py
```

**Requirements:**
- `API_GATEWAY_URL` environment variable
- `API_GATEWAY_KEY` environment variable (if API key authentication is used)
- Internet connectivity
- Valid AWS credentials for both partitions

### `test_vpn_routing.py`
Tests the new VPN-based routing approach via Lambda function.

**Features:**
- VPN tunnel connectivity validation
- Lambda VPC configuration verification
- VPC endpoint connectivity testing
- Bedrock inference via VPN routing
- Audit trail verification
- Performance baseline establishment

**Usage:**
```bash
# Load VPN configuration first
source config-vpn.sh

# Run VPN tests
python3 tests/test_vpn_routing.py
```

**Requirements:**
- VPN infrastructure deployed
- Lambda function configured for VPC
- `config-vpn.sh` loaded or `LAMBDA_FUNCTION_NAME` environment variable set
- Valid AWS credentials for both partitions

### `test_routing_comparison.py`
Comprehensive comparison between internet and VPN routing methods.

**Features:**
- Performance comparison
- Reliability comparison
- Security assessment
- Recommendations generation
- Comprehensive reporting

**Usage:**
```bash
python3 tests/test_routing_comparison.py
```

**Requirements:**
- Both internet and VPN routing configured
- All prerequisites from both individual test suites

### `test_vpn_connectivity.py`
Legacy VPN connectivity tests (original implementation).

## Test Runner Script

### `scripts/run-vpn-tests.sh`
Unified test runner for all routing tests.

**Usage:**
```bash
# Run both internet and VPN tests
./scripts/run-vpn-tests.sh

# Run specific test type
./scripts/run-vpn-tests.sh --test-type internet
./scripts/run-vpn-tests.sh --test-type vpn
./scripts/run-vpn-tests.sh --test-type comparison

# Run with specific configuration
./scripts/run-vpn-tests.sh --project-name my-project --environment prod
```

## Test Types

### Internet Routing Tests
- ✅ **API Gateway Endpoint**: Validates API Gateway availability
- ✅ **Bedrock Inference**: Tests AI inference via internet routing
- ✅ **Authentication**: Validates API key authentication
- ✅ **Audit Trail**: Verifies request logging
- ✅ **Performance**: Establishes performance baseline

### VPN Routing Tests
- ✅ **VPN Tunnel Connectivity**: Validates VPN tunnel status
- ✅ **Lambda VPC Configuration**: Verifies Lambda VPC setup
- ✅ **VPC Endpoint Connectivity**: Tests VPC endpoint access
- ✅ **Bedrock Inference**: Tests AI inference via VPN routing
- ✅ **Audit Trail**: Verifies request logging
- ✅ **Performance**: Establishes performance baseline

### Comparison Tests
- ⚖️ **Performance Comparison**: Compares response times
- 🛡️ **Reliability Comparison**: Compares success rates
- 🔒 **Security Assessment**: Evaluates security features
- 📋 **Recommendations**: Generates usage recommendations

## Configuration

### Environment Variables

**For Internet Routing:**
```bash
export API_GATEWAY_URL="https://api.example.com"
export API_GATEWAY_KEY="your-api-key"  # Optional
```

**For VPN Routing:**
```bash
# Load from config-vpn.sh (recommended)
source config-vpn.sh

# Or set manually
export LAMBDA_FUNCTION_NAME="cross-partition-inference-function"
export PROJECT_NAME="cross-partition-inference"
export ENVIRONMENT="dev"
```

**For Both:**
```bash
export PROJECT_NAME="cross-partition-inference"
export ENVIRONMENT="dev"
```

### AWS Profiles
Ensure AWS CLI profiles are configured:
```bash
aws configure --profile govcloud
aws configure --profile commercial
```

## Test Results

Test results are saved as JSON files with timestamps:
- `test-results-internet-YYYYMMDD-HHMMSS.json`
- `test-results-vpn-YYYYMMDD-HHMMSS.json`
- `test-results-comparison-YYYYMMDD-HHMMSS.json`

### Sample Test Result Structure
```json
{
  "test_suite": "internet_routing",
  "total_tests": 5,
  "successful_tests": 5,
  "failed_tests": 0,
  "success_rate": 100.0,
  "start_time": "2024-01-15T10:30:00.000Z",
  "end_time": "2024-01-15T10:35:00.000Z",
  "test_results": [
    {
      "test_name": "api_gateway_endpoint",
      "routing_method": "internet",
      "success": true,
      "response_time_ms": 150.5,
      "error": null
    }
  ]
}
```

## Troubleshooting

### Common Issues

**Internet Routing Tests Fail:**
- Verify `API_GATEWAY_URL` is set correctly
- Check API Gateway is deployed and accessible
- Verify API key if authentication is required
- Ensure internet connectivity

**VPN Routing Tests Fail:**
- Run `source config-vpn.sh` to load configuration
- Verify VPN tunnels are UP: `./scripts/get-vpn-status.sh`
- Check Lambda function is deployed in VPC
- Validate VPC endpoint connectivity

**Both Tests Fail:**
- Verify AWS CLI profiles are configured correctly
- Check AWS credentials have necessary permissions
- Ensure project name and environment match deployed resources

### Debug Mode
Run tests with Python's verbose mode:
```bash
python3 -v tests/test_internet_routing.py
python3 -v tests/test_vpn_routing.py
```

### Manual Testing
Test individual components:
```bash
# Test API Gateway directly
curl -H "x-api-key: YOUR_KEY" https://your-api-gateway-url/health

# Test Lambda function directly
aws lambda invoke --function-name your-function-name response.json

# Test VPN status
./scripts/get-vpn-status.sh
```

## Integration with CI/CD

### GitHub Actions Example
```yaml
name: Cross-Partition Routing Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Setup Python
        uses: actions/setup-python@v2
        with:
          python-version: '3.9'
      - name: Install dependencies
        run: pip install boto3 pytest requests
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      - name: Run routing tests
        run: ./scripts/run-vpn-tests.sh --test-type comparison
```

This test suite provides comprehensive validation of both routing methods, enabling confident deployment and operation of the cross-partition AI inference solution.