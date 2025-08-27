# Migration Guide: Internet to VPN Routing

This guide provides step-by-step procedures for migrating from the internet-based cross-partition AI inference solution to the VPN-based solution.

## Table of Contents

1. [Migration Overview](#migration-overview)
2. [Pre-Migration Assessment](#pre-migration-assessment)
3. [Migration Strategies](#migration-strategies)
4. [Step-by-Step Migration](#step-by-step-migration)
5. [Parallel Deployment Testing](#parallel-deployment-testing)
6. [Cutover Procedures](#cutover-procedures)
7. [Rollback Procedures](#rollback-procedures)
8. [Post-Migration Validation](#post-migration-validation)

## Migration Overview

### Current State (Internet-based)
- **Architecture**: API Gateway → Lambda → Internet → Commercial Bedrock
- **Security**: HTTPS encryption, API key authentication
- **Network**: Internet-dependent, public endpoints
- **Latency**: Variable based on internet conditions
- **Cost**: API Gateway charges, data transfer costs

### Target State (VPN-based)
- **Architecture**: Lambda (VPC) → VPN Tunnel → Commercial VPC → Bedrock VPC Endpoint
- **Security**: IPSec + HTTPS encryption, complete network isolation
- **Network**: Private connectivity, no internet dependencies
- **Latency**: Consistent, potentially lower
- **Cost**: VPN Gateway charges, reduced data transfer costs

### Migration Benefits
- ✅ **Enhanced Security**: Complete network isolation
- ✅ **Improved Compliance**: No internet exposure
- ✅ **Better Performance**: Consistent latency
- ✅ **Cost Optimization**: Reduced data transfer costs
- ✅ **Simplified Architecture**: Direct VPC connectivity

## Pre-Migration Assessment

### 1. Current Environment Analysis

Run the assessment script to analyze your current setup:

```bash
./scripts/run-vpn-tests.sh --test-type internet
```

**Key Metrics to Capture:**
- Current API Gateway endpoint URLs
- Average response times
- Request volume patterns
- Error rates
- Authentication mechanisms
- Audit trail format

### 2. Dependency Analysis

**Identify Dependencies:**
- Applications calling the API Gateway
- Monitoring systems
- Logging integrations
- Authentication systems
- Third-party integrations

**Create Dependency Map:**
```bash
# List all API Gateway integrations
aws apigateway get-rest-apis --profile govcloud --region us-gov-west-1

# Check CloudWatch logs for usage patterns
aws logs describe-log-groups --log-group-name-prefix "/aws/apigateway" \
    --profile govcloud --region us-gov-west-1
```

### 3. Performance Baseline

Establish current performance baselines:

```bash
# Run performance tests on current system
./scripts/run-vpn-tests.sh --test-type internet

# Capture baseline metrics
python3 tests/test_internet_routing.py
```

**Document Baseline Metrics:**
- Average response time
- 95th percentile response time
- Error rate
- Throughput (requests/second)
- Availability percentage

## Migration Strategies

### Strategy 1: Blue-Green Deployment (Recommended)

**Approach**: Deploy VPN solution alongside existing internet solution, then switch traffic.

**Pros:**
- Zero downtime migration
- Easy rollback
- Full testing before cutover
- Risk mitigation

**Cons:**
- Temporary increased costs
- More complex during transition

### Strategy 2: Phased Migration

**Approach**: Migrate traffic gradually by percentage or by client type.

**Pros:**
- Gradual risk exposure
- Ability to monitor impact
- Easier troubleshooting

**Cons:**
- Longer migration timeline
- Complex traffic routing
- Dual maintenance overhead

### Strategy 3: Big Bang Migration

**Approach**: Complete cutover in a single maintenance window.

**Pros:**
- Fastest migration
- Simplest approach
- Lower temporary costs

**Cons:**
- Higher risk
- Potential downtime
- Limited rollback options

## Step-by-Step Migration

### Phase 1: VPN Infrastructure Deployment

#### Step 1.1: Deploy VPN Infrastructure

```bash
# Deploy complete VPN solution
./scripts/deploy-vpn-with-config.sh \
    --project-name "cross-partition-inference" \
    --environment "prod" \
    --govcloud-profile "govcloud" \
    --commercial-profile "commercial"
```

#### Step 1.2: Validate VPN Deployment

```bash
# Validate VPN infrastructure
./scripts/validate-vpn-connectivity.sh --verbose

# Test VPN routing
./scripts/run-vpn-tests.sh --test-type vpn
```

#### Step 1.3: Performance Testing

```bash
# Run performance comparison
./scripts/run-vpn-tests.sh --test-type comparison

# Analyze results
python3 tests/test_routing_comparison.py
```

### Phase 2: Parallel Deployment Testing

#### Step 2.1: Configure Dual Routing

Update Lambda function to support both routing methods:

```python
# Add to Lambda function environment variables
ROUTING_METHOD = os.environ.get('ROUTING_METHOD', 'internet')  # Default to internet
ENABLE_DUAL_ROUTING = os.environ.get('ENABLE_DUAL_ROUTING', 'false')

def lambda_handler(event, context):
    # Check for routing method override in request
    routing_method = event.get('routing_method', ROUTING_METHOD)
    
    if routing_method == 'vpn':
        return handle_vpn_routing(event, context)
    else:
        return handle_internet_routing(event, context)
```

#### Step 2.2: Deploy Updated Lambda

```bash
# Update Lambda function with dual routing support
aws lambda update-function-code \
    --function-name "cross-partition-inference-function" \
    --zip-file fileb://lambda-deployment-package.zip \
    --profile govcloud \
    --region us-gov-west-1

# Update environment variables
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{
        "ROUTING_METHOD":"internet",
        "ENABLE_DUAL_ROUTING":"true",
        "VPC_ENDPOINT_SECRETS":"'$VPC_ENDPOINT_SECRETS'",
        "COMMERCIAL_BEDROCK_ENDPOINT":"'$COMMERCIAL_BEDROCK_ENDPOINT'"
    }' \
    --profile govcloud \
    --region us-gov-west-1
```

#### Step 2.3: Test Dual Routing

```bash
# Test internet routing (default)
aws lambda invoke \
    --function-name "cross-partition-inference-function" \
    --payload '{"model_id":"anthropic.claude-3-sonnet-20240229-v1:0","prompt":"Test internet routing"}' \
    response-internet.json

# Test VPN routing (explicit)
aws lambda invoke \
    --function-name "cross-partition-inference-function" \
    --payload '{"model_id":"anthropic.claude-3-sonnet-20240229-v1:0","prompt":"Test VPN routing","routing_method":"vpn"}' \
    response-vpn.json
```

### Phase 3: Gradual Traffic Migration

#### Step 3.1: Canary Testing (5% Traffic)

```bash
# Update Lambda to route 5% of traffic to VPN
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{
        "ROUTING_METHOD":"internet",
        "ENABLE_DUAL_ROUTING":"true",
        "VPN_TRAFFIC_PERCENTAGE":"5"
    }' \
    --profile govcloud \
    --region us-gov-west-1
```

**Monitor for 24 hours:**
- Error rates
- Response times
- VPN tunnel health
- Audit trail consistency

#### Step 3.2: Incremental Rollout

Gradually increase VPN traffic percentage:

```bash
# 25% VPN traffic
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{"VPN_TRAFFIC_PERCENTAGE":"25"}' \
    --profile govcloud --region us-gov-west-1

# Monitor for 24 hours, then continue...

# 50% VPN traffic
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{"VPN_TRAFFIC_PERCENTAGE":"50"}' \
    --profile govcloud --region us-gov-west-1

# 75% VPN traffic
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{"VPN_TRAFFIC_PERCENTAGE":"75"}' \
    --profile govcloud --region us-gov-west-1
```

#### Step 3.3: Monitor Migration Progress

```bash
# Continuous monitoring during migration
./scripts/validate-vpn-connectivity.sh --continuous

# Performance monitoring
./runbooks/performance-monitoring.sh monitor

# Check VPN tunnel health
./scripts/get-vpn-status.sh watch
```

### Phase 4: Complete Cutover

#### Step 4.1: Final Cutover

```bash
# Switch to 100% VPN routing
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{
        "ROUTING_METHOD":"vpn",
        "ENABLE_DUAL_ROUTING":"false"
    }' \
    --profile govcloud \
    --region us-gov-west-1
```

#### Step 4.2: Update API Gateway (Optional)

If keeping API Gateway for backward compatibility:

```bash
# Update API Gateway to point to VPN-enabled Lambda
aws apigateway update-integration \
    --rest-api-id "your-api-id" \
    --resource-id "your-resource-id" \
    --http-method POST \
    --patch-ops op=replace,path=/uri,value=arn:aws-us-gov:apigateway:us-gov-west-1:lambda:path/2015-03-31/functions/arn:aws-us-gov:lambda:us-gov-west-1:account:function:cross-partition-inference-function/invocations \
    --profile govcloud \
    --region us-gov-west-1
```

#### Step 4.3: Validate Complete Migration

```bash
# Run comprehensive validation
./scripts/run-vpn-tests.sh --test-type both

# Verify all traffic is using VPN
./scripts/validate-vpn-connectivity.sh --verbose
```

## Parallel Deployment Testing

### Test Environment Setup

Create a parallel test environment to validate the migration:

```bash
# Deploy test environment
./scripts/deploy-vpn-with-config.sh \
    --project-name "cross-partition-inference" \
    --environment "migration-test" \
    --govcloud-profile "govcloud" \
    --commercial-profile "commercial"
```

### Test Scenarios

#### Scenario 1: Functional Equivalence

```bash
# Test same requests through both methods
python3 tests/test_routing_comparison.py
```

**Validation Criteria:**
- Same response format
- Same response content
- Compatible error handling
- Consistent audit trail format

#### Scenario 2: Performance Comparison

```bash
# Run performance tests
./runbooks/performance-monitoring.sh baseline
```

**Validation Criteria:**
- Response time within acceptable range
- Error rate ≤ current system
- Throughput ≥ current system

#### Scenario 3: Load Testing

```bash
# Simulate production load
for i in {1..100}; do
    aws lambda invoke \
        --function-name "cross-partition-inference-migration-test" \
        --payload '{"model_id":"anthropic.claude-3-sonnet-20240229-v1:0","prompt":"Load test '$i'","routing_method":"vpn"}' \
        response-$i.json &
done
wait
```

## Cutover Procedures

### Pre-Cutover Checklist

- [ ] VPN infrastructure deployed and validated
- [ ] VPN tunnels are UP and stable
- [ ] Performance testing completed successfully
- [ ] Parallel testing shows functional equivalence
- [ ] Rollback procedures tested and validated
- [ ] Monitoring and alerting configured
- [ ] Stakeholders notified of cutover window
- [ ] Emergency contacts available

### Cutover Steps

#### 1. Pre-Cutover Validation (T-30 minutes)

```bash
# Final validation before cutover
./scripts/validate-vpn-connectivity.sh --verbose
./scripts/get-vpn-status.sh summary
```

#### 2. Traffic Cutover (T-0)

```bash
# Switch to VPN routing
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{"ROUTING_METHOD":"vpn"}' \
    --profile govcloud \
    --region us-gov-west-1
```

#### 3. Post-Cutover Validation (T+5 minutes)

```bash
# Immediate validation
./scripts/run-vpn-tests.sh --test-type vpn

# Test sample requests
aws lambda invoke \
    --function-name "cross-partition-inference-function" \
    --payload '{"model_id":"anthropic.claude-3-sonnet-20240229-v1:0","prompt":"Post-cutover validation test"}' \
    post-cutover-test.json
```

#### 4. Extended Monitoring (T+30 minutes)

```bash
# Monitor for 30 minutes
./scripts/validate-vpn-connectivity.sh --continuous
```

### Success Criteria

- [ ] All VPN tunnels remain UP
- [ ] Response times within expected range
- [ ] Error rate < 1%
- [ ] No critical alarms triggered
- [ ] Audit trail functioning correctly

## Rollback Procedures

### Immediate Rollback (< 5 minutes)

If issues are detected immediately after cutover:

```bash
# Emergency rollback to internet routing
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{"ROUTING_METHOD":"internet"}' \
    --profile govcloud \
    --region us-gov-west-1

# Validate rollback
./scripts/run-vpn-tests.sh --test-type internet
```

### Planned Rollback (Maintenance Window)

For planned rollback during a maintenance window:

#### Step 1: Prepare Rollback

```bash
# Ensure internet routing components are still available
aws apigateway get-rest-apis --profile govcloud --region us-gov-west-1

# Verify Lambda function can handle internet routing
aws lambda invoke \
    --function-name "cross-partition-inference-function" \
    --payload '{"routing_method":"internet","model_id":"test"}' \
    rollback-test.json
```

#### Step 2: Execute Rollback

```bash
# Switch back to internet routing
aws lambda update-function-configuration \
    --function-name "cross-partition-inference-function" \
    --environment Variables='{
        "ROUTING_METHOD":"internet",
        "ENABLE_DUAL_ROUTING":"false"
    }' \
    --profile govcloud \
    --region us-gov-west-1
```

#### Step 3: Validate Rollback

```bash
# Comprehensive validation
./scripts/run-vpn-tests.sh --test-type internet

# Performance validation
python3 tests/test_internet_routing.py
```

### Rollback Decision Matrix

| Issue | Severity | Action | Timeline |
|-------|----------|--------|----------|
| VPN tunnel down | High | Immediate rollback | < 5 minutes |
| High error rate (>5%) | High | Immediate rollback | < 5 minutes |
| Performance degradation (>50% slower) | Medium | Monitor 15 min, then rollback | 15 minutes |
| Minor issues | Low | Continue monitoring | 1 hour |

## Post-Migration Validation

### Immediate Validation (First 24 hours)

```bash
# Continuous monitoring
./scripts/validate-vpn-connectivity.sh --continuous

# Performance monitoring
./runbooks/performance-monitoring.sh monitor

# Generate migration report
python3 tests/test_routing_comparison.py
```

### Extended Validation (First Week)

#### Day 1-3: Intensive Monitoring
- Monitor every 15 minutes
- Check VPN tunnel health
- Validate performance metrics
- Review error logs

#### Day 4-7: Standard Monitoring
- Monitor every hour
- Weekly performance reports
- Capacity planning analysis

### Migration Success Metrics

#### Performance Metrics
- [ ] Average response time ≤ baseline + 20%
- [ ] 95th percentile response time ≤ baseline + 30%
- [ ] Error rate ≤ baseline
- [ ] Availability ≥ 99.9%

#### Security Metrics
- [ ] No internet traffic detected
- [ ] All traffic encrypted via VPN
- [ ] Audit trail complete and accurate
- [ ] No security incidents

#### Operational Metrics
- [ ] VPN tunnel uptime ≥ 99.9%
- [ ] Monitoring and alerting functional
- [ ] Documentation updated
- [ ] Team trained on new procedures

### Cleanup Activities

After successful migration (30 days):

#### Remove Internet-based Components

```bash
# Remove API Gateway (if no longer needed)
aws apigateway delete-rest-api \
    --rest-api-id "your-api-id" \
    --profile govcloud \
    --region us-gov-west-1

# Remove internet routing code from Lambda
# Update Lambda function to remove dual routing support

# Remove unused CloudWatch logs
aws logs delete-log-group \
    --log-group-name "/aws/apigateway/your-api-gateway" \
    --profile govcloud \
    --region us-gov-west-1
```

#### Update Documentation

- [ ] Update architecture diagrams
- [ ] Update operational procedures
- [ ] Update monitoring runbooks
- [ ] Update disaster recovery procedures

#### Cost Optimization

```bash
# Analyze cost savings
./runbooks/performance-monitoring.sh capacity --period 720

# Review and optimize VPN infrastructure
aws ec2 describe-vpn-connections --profile govcloud --region us-gov-west-1
```

## Migration Timeline Template

### Recommended Timeline (Production)

| Phase | Duration | Activities |
|-------|----------|------------|
| **Planning** | 2 weeks | Assessment, strategy, resource allocation |
| **Infrastructure** | 1 week | VPN deployment, validation |
| **Testing** | 2 weeks | Parallel testing, performance validation |
| **Migration** | 1 week | Gradual traffic migration |
| **Validation** | 1 week | Post-migration monitoring |
| **Cleanup** | 1 week | Remove old components, documentation |

### Accelerated Timeline (Non-Production)

| Phase | Duration | Activities |
|-------|----------|------------|
| **Planning** | 2 days | Quick assessment, strategy |
| **Infrastructure** | 1 day | VPN deployment |
| **Testing** | 2 days | Basic testing |
| **Migration** | 1 day | Direct cutover |
| **Validation** | 1 day | Post-migration validation |

This migration guide provides a comprehensive, step-by-step approach to safely migrate from internet-based to VPN-based routing while minimizing risk and ensuring business continuity.