# VPN Connectivity Troubleshooting Guide

This guide provides comprehensive troubleshooting procedures for the VPN connectivity solution.

## Table of Contents

1. [Quick Diagnostic Commands](#quick-diagnostic-commands)
2. [VPN Tunnel Issues](#vpn-tunnel-issues)
3. [Lambda Function Issues](#lambda-function-issues)
4. [VPC Endpoint Issues](#vpc-endpoint-issues)
5. [Cross-Partition Authentication](#cross-partition-authentication)
6. [Network Connectivity Issues](#network-connectivity-issues)
7. [Performance Issues](#performance-issues)
8. [Monitoring and Alerting](#monitoring-and-alerting)

## Quick Diagnostic Commands

### Check Overall System Status
```bash
# Load configuration
source config-vpn.sh

# Quick status check
./scripts/get-vpn-status.sh summary

# Comprehensive validation
./scripts/validate-vpn-connectivity.sh --verbose

# Show VPN routing
show_vpn_routing
```

### Check VPN Tunnel Status
```bash
# GovCloud VPN status
aws ec2 describe-vpn-connections \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'VpnConnections[*].{ID:VpnConnectionId,State:State,Tunnels:VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status,Message:StatusMessage}}'

# Commercial VPN status  
aws ec2 describe-vpn-connections \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --profile "$COMMERCIAL_PROFILE" \
    --region us-east-1 \
    --query 'VpnConnections[*].{ID:VpnConnectionId,State:State,Tunnels:VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status,Message:StatusMessage}}'
```### 
Check Lambda Function Status
```bash
# Lambda function configuration
aws lambda get-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Recent Lambda logs
aws logs tail "$CLOUDWATCH_LOG_GROUP" --since 1h \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Lambda metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1
```

### Check VPC Endpoint Status
```bash
# List VPC endpoints
aws ec2 describe-vpc-endpoints \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'VpcEndpoints[*].{Service:ServiceName,State:State,DNS:DnsEntries[0].DnsName}'

# Test endpoint connectivity
timeout 5 nc -zv $(echo $VPC_ENDPOINT_SECRETS | cut -d'.' -f1) 443
```

## VPN Tunnel Issues

### Issue: VPN Tunnels Not Establishing

**Symptoms:**
- VPN connection state shows "available" but tunnels are "DOWN"
- No BGP routes being advertised
- Cannot ping across partitions

**Diagnostic Steps:**
```bash
# Check tunnel detailed status
aws ec2 describe-vpn-connections \
    --vpn-connection-ids "$GOVCLOUD_VPN_CONNECTION_ID" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'VpnConnections[0].VgwTelemetry[*]'

# Check Customer Gateway configuration
aws ec2 describe-customer-gateways \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1
```**Co
mmon Causes and Solutions:**

1. **Incorrect Customer Gateway IP**
   ```bash
   # Verify your public IP
   curl -s https://checkip.amazonaws.com
   
   # Update Customer Gateway if needed
   aws ec2 modify-vpn-connection \
       --vpn-connection-id "$GOVCLOUD_VPN_CONNECTION_ID" \
       --customer-gateway-id "$NEW_CUSTOMER_GATEWAY_ID"
   ```

2. **Firewall Blocking IPSec Traffic**
   - Ensure UDP 500 (IKE) is allowed
   - Ensure UDP 4500 (IPSec NAT-T) is allowed  
   - Ensure IP protocol 50 (ESP) is allowed

3. **Pre-shared Key Mismatch**
   ```bash
   # Check CloudFormation parameters
   aws cloudformation describe-stacks \
       --stack-name "$PROJECT_NAME-govcloud-vpn-$ENVIRONMENT" \
       --profile "$GOVCLOUD_PROFILE" \
       --region us-gov-west-1 \
       --query 'Stacks[0].Parameters'
   ```

4. **BGP ASN Conflicts**
   ```bash
   # Check BGP ASN configuration
   aws ec2 describe-customer-gateways \
       --customer-gateway-ids "$CUSTOMER_GATEWAY_ID" \
       --query 'CustomerGateways[0].BgpAsn'
   ```

### Issue: VPN Tunnels Flapping

**Symptoms:**
- Tunnels going UP and DOWN repeatedly
- Intermittent connectivity
- High packet loss

**Diagnostic Steps:**
```bash
# Monitor tunnel status changes
watch -n 30 './scripts/get-vpn-status.sh summary'

# Check for route conflicts
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$GOVCLOUD_VPC_ID" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'RouteTables[*].Routes'
```

**Solutions:**
1. **Check network stability on customer side**
2. **Verify BGP keepalive settings**
3. **Check for MTU issues**
4. **Review firewall logs for dropped packets**

## Lambda Function Issues

### Issue: Lambda Function Timeouts

**Symptoms:**
- Lambda functions timing out
- No response from cross-partition calls
- CloudWatch logs show timeout errors

**Diagnostic Steps:**
```bash
# Check Lambda timeout configuration
aws lambda get-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query '{Timeout:Timeout,MemorySize:MemorySize,VpcConfig:VpcConfig}'

# Check recent errors
aws logs filter-log-events \
    --log-group-name "$CLOUDWATCH_LOG_GROUP" \
    --filter-pattern "ERROR" \
    --start-time $(date -d '1 hour ago' +%s)000 \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1
```**Solutions
:**
1. **Increase Lambda timeout** (max 15 minutes)
2. **Check VPC endpoint connectivity**
3. **Verify security group rules**
4. **Check VPN tunnel status**

### Issue: Lambda Cold Start Issues

**Symptoms:**
- First requests taking very long
- Intermittent timeouts
- High latency for initial requests

**Solutions:**
```bash
# Enable provisioned concurrency
aws lambda put-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --provisioned-concurrency-config ProvisionedConcurrencyCount=2 \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Check cold start metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name InitDuration \
    --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum
```

## VPC Endpoint Issues

### Issue: Cannot Reach VPC Endpoints

**Symptoms:**
- DNS resolution failures for AWS services
- Connection timeouts to VPC endpoints
- SSL/TLS handshake failures

**Diagnostic Steps:**
```bash
# Test DNS resolution
nslookup secretsmanager.us-gov-west-1.amazonaws.com

# Test connectivity
nc -zv secretsmanager.us-gov-west-1.amazonaws.com 443

# Check VPC endpoint status
aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$GOVCLOUD_VPC_ID" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'VpcEndpoints[*].{Service:ServiceName,State:State,DNS:DnsEntries[0].DnsName}'
```

**Solutions:**
1. **Verify VPC DNS settings**
   ```bash
   aws ec2 describe-vpcs \
       --vpc-ids "$GOVCLOUD_VPC_ID" \
       --query 'Vpcs[0].{DnsHostnames:DnsHostnames,DnsSupport:DnsSupport}'
   ```

2. **Check security group rules**
   ```bash
   aws ec2 describe-security-groups \
       --group-ids "$VPC_ENDPOINT_SG_ID" \
       --query 'SecurityGroups[0].IpPermissions'
   ```

3. **Verify route table associations**
   ```bash
   aws ec2 describe-route-tables \
       --filters "Name=association.subnet-id,Values=$VPC_ENDPOINT_SUBNET_ID" \
       --query 'RouteTables[0].Routes'
   ```

## Cross-Partition Authentication

### Issue: Access Denied Errors

**Symptoms:**
- "Access Denied" when calling Bedrock
- "Invalid credentials" errors
- Authentication failures in logs

**Diagnostic Steps:**
```bash
# Check commercial credentials secret
aws secretsmanager get-secret-value \
    --secret-id "$COMMERCIAL_CREDENTIALS_SECRET" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'SecretString' \
    --output text | jq '.'

# Test credentials manually
aws sts get-caller-identity \
    --profile "$COMMERCIAL_PROFILE" \
    --region us-east-1
```**So
lutions:**
1. **Verify IAM permissions in Commercial account**
2. **Check credential rotation**
3. **Validate secret format**
4. **Test direct API calls**

### Issue: Token Expiration

**Symptoms:**
- Intermittent authentication failures
- "Token expired" errors
- Authentication works initially then fails

**Solutions:**
```bash
# Implement credential caching with TTL
# Check token expiration in Lambda logs
# Implement automatic token refresh
```

## Network Connectivity Issues

### Issue: Cannot Route Between Partitions

**Symptoms:**
- Packets not reaching destination
- Routing loops
- Asymmetric routing

**Diagnostic Steps:**
```bash
# Check route tables
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$GOVCLOUD_VPC_ID" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Check VPN route propagation
aws ec2 describe-vpn-connections \
    --vpn-connection-ids "$GOVCLOUD_VPN_CONNECTION_ID" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'VpnConnections[0].Routes'

# Enable VPC Flow Logs for debugging
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids "$GOVCLOUD_VPC_ID" \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name "/aws/vpc/flowlogs"
```

## Performance Issues

### Issue: High Latency

**Symptoms:**
- Slow response times
- Timeouts under load
- Poor user experience

**Diagnostic Steps:**
```bash
# Check VPN tunnel latency
# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/VPN \
    --metric-name TunnelLatency \
    --dimensions Name=VpnId,Value="$GOVCLOUD_VPN_CONNECTION_ID" \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Average,Maximum

# Check Lambda performance
source config-vpn.sh
show_vpn_status
```

**Solutions:**
1. **Optimize Lambda memory allocation**
2. **Implement connection pooling**
3. **Use response caching**
4. **Optimize payload sizes**

## Monitoring and Alerting

### Set Up Comprehensive Monitoring

```bash
# Create CloudWatch dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "$PROJECT_NAME-vpn-health" \
    --dashboard-body file://monitoring/vpn-dashboard.json

# Set up critical alarms
aws cloudwatch put-metric-alarm \
    --alarm-name "$PROJECT_NAME-vpn-tunnel-down" \
    --alarm-description "VPN tunnel is down" \
    --metric-name TunnelState \
    --namespace AWS/VPN \
    --statistic Maximum \
    --period 300 \
    --threshold 0 \
    --comparison-operator LessThanThreshold \
    --evaluation-periods 2
```

### Emergency Response Procedures

1. **VPN Complete Outage**
   - Check AWS Service Health Dashboard
   - Verify customer-side network connectivity
   - Contact AWS Support if needed
   - Implement fallback procedures

2. **Lambda Function Failures**
   - Check CloudWatch logs
   - Verify VPC configuration
   - Test VPC endpoint connectivity
   - Restart Lambda if needed

3. **Authentication Issues**
   - Verify credentials in Secrets Manager
   - Check IAM permissions
   - Test manual API calls
   - Rotate credentials if compromised

For additional help, see the [VPN-Operations-Guide.md](VPN-Operations-Guide.md).