# Troubleshooting Guide

Common issues and solutions for the Cross-Partition Bedrock Inference system.

## 🚨 Quick Diagnostics

### Run System Health Check
```bash
# Comprehensive system validation
./scripts/run-comprehensive-validation.sh

# Quick setup validation
./scripts/validate-setup.sh

# Security scan
./scripts/security-scan.sh
```

## 🔧 Common Issues & Solutions

### 1. Deployment Failures

#### CloudFormation Stack Creation Failed
**Symptoms:**
- Stack creation fails with permission errors
- Resources not created properly

**Solutions:**
```bash
# Check AWS credentials and permissions
aws sts get-caller-identity

# Validate setup requirements
./scripts/validate-setup.sh

# Check CloudFormation events
aws cloudformation describe-stack-events --stack-name CrossPartitionInference
```

#### Lambda Function Deployment Failed
**Symptoms:**
- Lambda functions not created or updated
- Deployment package too large

**Solutions:**
```bash
# Rebuild Lambda packages
./scripts/package-lambda-functions.sh

# Check Lambda function logs
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/CrossPartition"
```

### 2. Authentication Issues

#### Bearer Token Authentication Failed
**Symptoms:**
- 401 Unauthorized errors
- "Invalid bearer token" messages

**Solutions:**
```bash
# Update bearer token
./scripts/update-bearer-token-secret.sh

# Test bearer token functionality
./scripts/test-bearer-token-functionality.sh

# Check Secrets Manager
aws secretsmanager get-secret-value --secret-id cross-partition-bearer-token
```

#### Commercial Credentials Invalid
**Symptoms:**
- 403 Forbidden errors from Bedrock
- "Invalid API key" messages

**Solutions:**
```bash
# Check commercial credentials
aws secretsmanager get-secret-value --secret-id cross-partition-commercial-creds

# Update with valid Bedrock API key
aws secretsmanager update-secret \
  --secret-id cross-partition-commercial-creds \
  --secret-string '{"bedrock_api_key": "YOUR_VALID_KEY", "region": "us-east-1"}'
```

### 3. Network Connectivity Issues

#### VPN Tunnel Connectivity Failed
**Symptoms:**
- VPN tests fail with timeout errors
- Cannot reach commercial partition

**Solutions:**
```bash
# Test VPN connectivity
./scripts/validate-vpn-connectivity.sh

# Check VPN tunnel status
./scripts/test-vpn-tunnel-connectivity.sh

# Comprehensive VPN testing
./scripts/test-vpn-comprehensive.sh
```

#### Internet Connectivity Issues
**Symptoms:**
- Timeouts on internet-based requests
- DNS resolution failures

**Solutions:**
```bash
# Test internet connectivity
./scripts/test-internet-lambda-unit.sh

# Check API Gateway integration
./scripts/test-api-gateway-integration.sh

# Validate endpoints
./scripts/test-dual-routing-endpoints.sh
```

### 4. Model Access Issues

#### Model Not Available
**Symptoms:**
- "Model not found" errors
- Invalid model ID messages

**Solutions:**
```bash
# List available models
curl -X GET "$API_BASE_URL/bedrock/models" \
  -H "Authorization: Bearer YOUR_TOKEN"

# Test specific model
./scripts/test-claude-4-1.sh

# Test multiple models
./scripts/test-cross-partition.sh
```

#### Rate Limiting Issues
**Symptoms:**
- 429 Too Many Requests errors
- Throttling messages

**Solutions:**
```bash
# Check CloudWatch metrics for rate limits
aws cloudwatch get-metric-statistics \
  --namespace "CrossPartition/Bedrock" \
  --metric-name "ThrottledRequests"

# Implement exponential backoff in your application
# Reduce request frequency
```

### 5. Performance Issues

#### High Latency
**Symptoms:**
- Slow response times
- Timeout errors

**Solutions:**
```bash
# Run performance comparison
./scripts/run-performance-comparison.sh

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace "CrossPartition/Bedrock" \
  --metric-name "ResponseTime"

# Test monitoring dashboard
./scripts/test-monitoring-dashboard.sh
```

#### Memory or Timeout Issues
**Symptoms:**
- Lambda timeout errors
- Out of memory errors

**Solutions:**
```bash
# Check Lambda function configuration
aws lambda get-function --function-name CrossPartitionInternetLambda

# Update Lambda memory/timeout if needed
aws lambda update-function-configuration \
  --function-name CrossPartitionInternetLambda \
  --memory-size 512 \
  --timeout 30
```

## 🔍 Diagnostic Commands

### System Status
```bash
# Overall system health
./scripts/run-comprehensive-validation.sh

# Component-specific tests
./scripts/test-api-gateway-deployment.sh
./scripts/test-dual-routing-auth.sh
./scripts/test-monitoring-dashboard.sh
```

### Log Analysis
```bash
# Lambda function logs
aws logs tail /aws/lambda/CrossPartitionInternetLambda --follow

# API Gateway logs
aws logs tail /aws/apigateway/CrossPartitionAPI --follow

# VPC Flow Logs (if VPN deployed)
aws logs tail /aws/vpc/flowlogs --follow
```

### Configuration Validation
```bash
# Check configuration files
source config/config.sh
echo "API Base URL: $API_BASE_URL"
echo "Stack Name: $STACK_NAME"

# Validate CloudFormation stack
aws cloudformation describe-stacks --stack-name $STACK_NAME
```

## 🚨 Error Code Reference

### HTTP Status Codes
| Code | Meaning | Common Causes | Solutions |
|------|---------|---------------|-----------|
| 400 | Bad Request | Invalid JSON, missing parameters | Check request format |
| 401 | Unauthorized | Invalid bearer token | Update token in Secrets Manager |
| 403 | Forbidden | Invalid Bedrock API key | Update commercial credentials |
| 404 | Not Found | Invalid endpoint or model | Check API endpoints and model IDs |
| 429 | Rate Limited | Too many requests | Implement backoff, reduce frequency |
| 500 | Internal Error | Lambda function error | Check Lambda logs |
| 502 | Bad Gateway | Upstream service error | Check commercial partition connectivity |
| 503 | Service Unavailable | Service overloaded | Retry with exponential backoff |

### AWS Service Errors
| Service | Error | Cause | Solution |
|---------|-------|-------|---------|
| Lambda | Function timeout | Long-running request | Increase timeout, optimize code |
| API Gateway | Integration timeout | Backend service slow | Check Lambda performance |
| Secrets Manager | AccessDenied | IAM permissions | Update IAM roles |
| DynamoDB | ThrottlingException | High write volume | Enable auto-scaling |
| VPC | Network timeout | VPN connectivity | Check VPN tunnel status |

## 🔧 Advanced Troubleshooting

### Enable Debug Logging
```bash
# Set debug environment variables
export DEBUG=true
export LOG_LEVEL=DEBUG

# Run tests with verbose output
./scripts/test-cross-partition.sh --verbose
```

### Manual Testing
```bash
# Test individual components
curl -X POST "$API_BASE_URL/bedrock/invoke-model" \
  -H "Authorization: Bearer $BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "modelId": "anthropic.claude-3-5-sonnet-20241022-v2:0",
    "body": {
      "anthropic_version": "bedrock-2023-05-31",
      "max_tokens": 100,
      "messages": [{"role": "user", "content": "Hello"}]
    }
  }' | jq '.'
```

### Performance Profiling
```bash
# Run load testing
./scripts/run-load-testing.sh

# Monitor CloudWatch metrics
aws cloudwatch get-dashboard --dashboard-name CrossPartitionDashboard
```

## 📞 Getting Help

### Self-Service Resources
1. **Scripts Reference**: [docs/SCRIPTS_REFERENCE.md](SCRIPTS_REFERENCE.md)
2. **Setup Guide**: [docs/SETUP_GUIDE.md](SETUP_GUIDE.md)
3. **Architecture Guide**: [docs/ARCHITECTURE.md](ARCHITECTURE.md)

### Diagnostic Information to Collect
When seeking help, provide:
- Output from `./scripts/validate-setup.sh`
- CloudFormation stack events
- Lambda function logs
- Error messages and stack traces
- Configuration files (redacted)

### Common Resolution Steps
1. **Validate setup**: Run `./scripts/validate-setup.sh`
2. **Check credentials**: Verify Secrets Manager values
3. **Test connectivity**: Run appropriate connectivity tests
4. **Review logs**: Check CloudWatch logs for errors
5. **Update configuration**: Ensure all config files are current

## 🔄 Recovery Procedures

### Complete System Reset
```bash
# Clean up existing deployment
aws cloudformation delete-stack --stack-name CrossPartitionInference

# Wait for deletion to complete
aws cloudformation wait stack-delete-complete --stack-name CrossPartitionInference

# Redeploy from scratch
./scripts/deploy-over-internet.sh
```

### Partial Component Recovery
```bash
# Redeploy specific components
./scripts/deploy-dual-routing-api-gateway.sh
./scripts/deploy-dual-routing-auth.sh
./scripts/deploy-dual-routing-monitoring.sh
```

### Configuration Recovery
```bash
# Regenerate configuration
./scripts/get-config.sh

# Validate configuration
source config/config.sh
./scripts/validate-setup.sh
```