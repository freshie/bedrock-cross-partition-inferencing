# VPN Connectivity Operations Guide

This guide provides comprehensive operational procedures for managing the VPN connectivity solution in production.

## Table of Contents

1. [Daily Operations](#daily-operations)
2. [Monitoring and Alerting](#monitoring-and-alerting)
3. [Incident Response](#incident-response)
4. [Maintenance Procedures](#maintenance-procedures)
5. [Performance Monitoring](#performance-monitoring)
6. [Security Operations](#security-operations)
7. [Capacity Planning](#capacity-planning)
8. [Disaster Recovery](#disaster-recovery)

## Daily Operations

### Morning Health Check

Execute this checklist every morning to ensure system health:

```bash
#!/bin/bash
# Daily VPN Health Check Script

echo "=== Daily VPN Health Check - $(date) ==="

# Load configuration
source config-vpn.sh

# 1. Check VPN tunnel status
echo "1. Checking VPN tunnel status..."
./scripts/get-vpn-status.sh summary

# 2. Validate configuration
echo "2. Validating configuration..."
validate_vpn_config

# 3. Test connectivity
echo "3. Testing connectivity..."
test_vpn_connectivity

# 4. Check Lambda function health
echo "4. Checking Lambda function health..."
aws lambda get-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'Configuration.{State:State,LastModified:LastModified}'

# 5. Check recent errors
echo "5. Checking recent errors..."
aws logs filter-log-events \
    --log-group-name "$CLOUDWATCH_LOG_GROUP" \
    --filter-pattern "ERROR" \
    --start-time $(date -d '24 hours ago' +%s)000 \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'events[*].{Time:timestamp,Message:message}' \
    --output table

# 6. Check CloudWatch alarms
echo "6. Checking CloudWatch alarms..."
aws cloudwatch describe-alarms \
    --state-value ALARM \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'MetricAlarms[?contains(AlarmName, `'$PROJECT_NAME'`)].{Name:AlarmName,State:StateValue,Reason:StateReason}'

echo "=== Health check completed ==="
```

### Weekly Maintenance Tasks

**Every Monday:**
1. Review performance metrics from previous week
2. Check for AWS service updates
3. Review security logs and audit trails
4. Update documentation if needed
5. Test backup and recovery procedures

**Weekly Checklist:**
```bash
# Weekly maintenance script
./scripts/validate-vpn-connectivity.sh --verbose
./scripts/get-vpn-status.sh
aws cloudwatch get-metric-statistics \
    --namespace AWS/VPN \
    --metric-name TunnelState \
    --dimensions Name=VpnId,Value="$GOVCLOUD_VPN_CONNECTION_ID" \
    --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average
```

## Monitoring and Alerting

### CloudWatch Dashboard Configuration

Create a comprehensive monitoring dashboard:

```json
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/VPN", "TunnelState", "VpnId", "vpn-12345678"],
                    ["AWS/Lambda", "Duration", "FunctionName", "cross-partition-inference"],
                    ["AWS/Lambda", "Errors", "FunctionName", "cross-partition-inference"],
                    ["AWS/Lambda", "Invocations", "FunctionName", "cross-partition-inference"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "us-gov-west-1",
                "title": "VPN and Lambda Health"
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/cross-partition-inference'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 20",
                "region": "us-gov-west-1",
                "title": "Recent Errors"
            }
        }
    ]
}
```

### Critical Alarms

**VPN Tunnel Down Alarm:**
```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "${PROJECT_NAME}-vpn-tunnel-down" \
    --alarm-description "VPN tunnel is down" \
    --metric-name TunnelState \
    --namespace AWS/VPN \
    --statistic Maximum \
    --period 300 \
    --threshold 0 \
    --comparison-operator LessThanThreshold \
    --dimensions Name=VpnId,Value="$GOVCLOUD_VPN_CONNECTION_ID" \
    --evaluation-periods 2 \
    --alarm-actions "arn:aws-us-gov:sns:us-gov-west-1:123456789012:vpn-alerts" \
    --treat-missing-data breaching
```

**Lambda Error Rate Alarm:**
```bash
aws cloudwatch put-metric-alarm \
    --alarm-name "${PROJECT_NAME}-lambda-error-rate" \
    --alarm-description "Lambda error rate is high" \
    --metric-name ErrorRate \
    --namespace AWS/Lambda \
    --statistic Average \
    --period 300 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
    --evaluation-periods 3 \
    --alarm-actions "arn:aws-us-gov:sns:us-gov-west-1:123456789012:vpn-alerts"
```

### Performance Monitoring

**Key Metrics to Monitor:**

1. **VPN Tunnel Health**
   - Tunnel state (UP/DOWN)
   - Tunnel latency
   - Packet drop rate
   - BGP route count

2. **Lambda Performance**
   - Invocation count
   - Duration
   - Error rate
   - Cold start frequency

3. **Cross-Partition Latency**
   - End-to-end request time
   - VPN traversal time
   - Bedrock response time

4. **VPC Endpoint Health**
   - Endpoint availability
   - DNS resolution time
   - Connection success rate

## Incident Response

### Severity Levels

**Severity 1 (Critical)**
- Complete VPN outage
- All Lambda functions failing
- Security breach detected

**Severity 2 (High)**
- Single VPN tunnel down
- High error rates (>10%)
- Performance degradation

**Severity 3 (Medium)**
- Intermittent issues
- Non-critical alarms
- Performance concerns

**Severity 4 (Low)**
- Documentation updates needed
- Minor configuration issues
- Informational alerts

### Incident Response Procedures

#### Severity 1: Complete VPN Outage

**Immediate Actions (0-15 minutes):**
1. Acknowledge the incident
2. Check AWS Service Health Dashboard
3. Verify customer-side network connectivity
4. Check VPN tunnel status in both partitions

**Investigation (15-30 minutes):**
```bash
# Check VPN connection status
aws ec2 describe-vpn-connections \
    --vpn-connection-ids "$GOVCLOUD_VPN_CONNECTION_ID" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Check Customer Gateway status
aws ec2 describe-customer-gateways \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Check recent CloudTrail events
aws logs filter-log-events \
    --log-group-name "CloudTrail/VPNEvents" \
    --start-time $(date -d '2 hours ago' +%s)000 \
    --filter-pattern "{ $.eventName = CreateVpnConnection || $.eventName = DeleteVpnConnection }"
```

**Resolution Actions:**
1. Reset VPN connection if needed
2. Update Customer Gateway IP if changed
3. Contact AWS Support for service issues
4. Implement emergency fallback procedures

#### Severity 2: Single VPN Tunnel Down

**Investigation:**
```bash
# Check specific tunnel status
aws ec2 describe-vpn-connections \
    --vpn-connection-ids "$GOVCLOUD_VPN_CONNECTION_ID" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'VpnConnections[0].VgwTelemetry'

# Check BGP routing
aws ec2 describe-vpn-connections \
    --vpn-connection-ids "$GOVCLOUD_VPN_CONNECTION_ID" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query 'VpnConnections[0].Routes'
```

**Resolution:**
1. Monitor for automatic recovery (BGP failover)
2. Check customer-side firewall logs
3. Verify pre-shared keys
4. Reset tunnel if necessary

### Escalation Procedures

**Level 1: Operations Team**
- Monitor and respond to alerts
- Execute standard procedures
- Escalate if unable to resolve in 30 minutes

**Level 2: Engineering Team**
- Deep technical investigation
- Code changes if needed
- Architecture modifications

**Level 3: AWS Support**
- Service-level issues
- Infrastructure problems
- Emergency support cases

## Maintenance Procedures

### Planned Maintenance Windows

**Monthly Maintenance (First Saturday of each month, 2-6 AM UTC):**

1. **Pre-maintenance Checklist:**
   ```bash
   # Backup current configuration
   ./scripts/extract-vpn-config.sh --output-dir ./backup/$(date +%Y%m%d)
   
   # Document current state
   ./scripts/get-vpn-status.sh > ./backup/$(date +%Y%m%d)/pre-maintenance-status.txt
   
   # Verify rollback procedures
   ./scripts/validate-vpn-connectivity.sh --verbose
   ```

2. **Maintenance Activities:**
   - Update Lambda function code
   - Rotate credentials
   - Update CloudFormation stacks
   - Apply security patches

3. **Post-maintenance Validation:**
   ```bash
   # Comprehensive validation
   ./scripts/validate-vpn-connectivity.sh --verbose
   
   # Performance testing
   ./scripts/run-vpn-tests.sh
   
   # Generate post-maintenance report
   ./scripts/get-vpn-status.sh > ./reports/$(date +%Y%m%d)/post-maintenance-status.txt
   ```

### Emergency Maintenance

**Unplanned maintenance procedures:**

1. **Assess Impact:**
   - Determine affected services
   - Estimate downtime
   - Notify stakeholders

2. **Execute Changes:**
   - Follow change management procedures
   - Document all actions
   - Monitor system health

3. **Validate and Report:**
   - Confirm resolution
   - Update documentation
   - Conduct post-incident review

## Performance Monitoring

### Performance Baselines

**Normal Operating Parameters:**
- VPN tunnel latency: < 50ms
- Lambda duration: < 5 seconds
- Error rate: < 1%
- Availability: > 99.9%

### Performance Optimization

**Weekly Performance Review:**
```bash
# Generate performance report
aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name Duration \
    --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
    --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average,Maximum,Minimum

# Check for performance degradation
aws cloudwatch get-metric-statistics \
    --namespace AWS/VPN \
    --metric-name TunnelLatency \
    --dimensions Name=VpnId,Value="$GOVCLOUD_VPN_CONNECTION_ID" \
    --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Average,Maximum
```

## Security Operations

### Security Monitoring

**Daily Security Checks:**
1. Review VPC Flow Logs for anomalies
2. Check CloudTrail for unauthorized API calls
3. Verify IAM permissions haven't changed
4. Monitor failed authentication attempts

**Security Incident Response:**
```bash
# Check for suspicious activity
aws logs filter-log-events \
    --log-group-name "/aws/vpc/flowlogs" \
    --filter-pattern "{ $.action = \"REJECT\" }" \
    --start-time $(date -d '24 hours ago' +%s)000

# Review API calls
aws logs filter-log-events \
    --log-group-name "CloudTrail/APILogs" \
    --filter-pattern "{ $.errorCode exists }" \
    --start-time $(date -d '24 hours ago' +%s)000
```

### Credential Rotation

**Monthly credential rotation:**
```bash
# Rotate commercial credentials
aws secretsmanager update-secret \
    --secret-id "$COMMERCIAL_CREDENTIALS_SECRET" \
    --secret-string '{
        "access_key_id": "NEW_ACCESS_KEY",
        "secret_access_key": "NEW_SECRET_KEY",
        "region": "us-east-1"
    }' \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Test new credentials
aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --payload '{"test": "credential_rotation"}' \
    response.json
```

## Capacity Planning

### Usage Monitoring

**Monthly capacity review:**
- Lambda invocation trends
- VPN bandwidth utilization
- VPC endpoint data processing
- Storage growth patterns

### Scaling Procedures

**Lambda Scaling:**
```bash
# Update Lambda memory if needed
aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --memory-size 1024 \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Enable provisioned concurrency for high load
aws lambda put-provisioned-concurrency-config \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --provisioned-concurrency-config ProvisionedConcurrencyCount=5
```

## Disaster Recovery

### Backup Procedures

**Daily Backups:**
```bash
# Backup configuration
./scripts/extract-vpn-config.sh --output-dir ./backups/$(date +%Y%m%d)

# Backup CloudFormation templates
aws s3 sync ./infrastructure/ s3://backup-bucket/templates/$(date +%Y%m%d)/

# Export CloudWatch dashboards
aws cloudwatch get-dashboard \
    --dashboard-name "$PROJECT_NAME-vpn-health" > ./backups/$(date +%Y%m%d)/dashboard.json
```

### Recovery Procedures

**Complete Infrastructure Recovery:**
1. Deploy infrastructure from templates
2. Restore configuration from backups
3. Update DNS and routing
4. Validate all connections
5. Resume normal operations

**Partial Recovery:**
- Single component failures
- Configuration restoration
- Service-specific recovery

This operations guide provides the foundation for reliable, secure operation of the VPN connectivity solution. Regular review and updates ensure continued effectiveness.