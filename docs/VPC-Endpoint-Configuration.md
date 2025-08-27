# VPC Endpoint Configuration Guide

This guide provides detailed instructions for configuring VPC endpoints in the VPN connectivity solution. VPC endpoints eliminate the need for NAT gateways and provide secure, private access to AWS services.

## Table of Contents

1. [Overview](#overview)
2. [VPC Endpoint Types](#vpc-endpoint-types)
3. [GovCloud VPC Endpoints](#govcloud-vpc-endpoints)
4. [Commercial VPC Endpoints](#commercial-vpc-endpoints)
5. [Security Configuration](#security-configuration)
6. [DNS Configuration](#dns-configuration)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

## Overview

VPC endpoints provide private connectivity to AWS services without requiring internet access. In the VPN connectivity solution, VPC endpoints are essential for:

- **Complete Network Isolation**: No internet gateways required
- **Enhanced Security**: Traffic stays within AWS network
- **Improved Performance**: Reduced latency and higher bandwidth
- **Cost Optimization**: No NAT gateway charges

## VPC Endpoint Types

### Interface Endpoints (AWS PrivateLink)

Interface endpoints create elastic network interfaces (ENIs) in your VPC subnets and provide private IP addresses for AWS services.

**Characteristics:**
- Use private DNS names
- Support security groups
- Charge per hour and per GB processed
- Support multiple Availability Zones

### Gateway Endpoints

Gateway endpoints are route table entries that direct traffic to AWS services through the AWS network.

**Characteristics:**
- No additional charges
- Only available for S3 and DynamoDB
- Use route table entries
- Regional service

## GovCloud VPC Endpoints

The GovCloud partition requires VPC endpoints for Lambda functions to access AWS services without internet connectivity.

### Required Endpoints

#### 1. Secrets Manager Endpoint

**Purpose**: Access commercial partition credentials and other secrets

**Configuration:**
```yaml
SecretsManagerEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.secretsmanager'
    VpcEndpointType: Interface
    SubnetIds:
      - !Ref VPCEndpointSubnet
    SecurityGroupIds:
      - !Ref VPCEndpointSecurityGroup
    PrivateDnsEnabled: true
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal: '*'
          Action:
            - secretsmanager:GetSecretValue
            - secretsmanager:DescribeSecret
          Resource: 
            - !Sub 'arn:${AWS::Partition}:secretsmanager:${AWS::Region}:${AWS::AccountId}:secret:${ProjectName}-*'
```

**DNS Name**: `secretsmanager.us-gov-west-1.amazonaws.com`

#### 2. DynamoDB Endpoint

**Purpose**: Store request logs and audit trails

**Configuration:**
```yaml
DynamoDBEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.dynamodb'
    VpcEndpointType: Gateway
    RouteTableIds:
      - !Ref PrivateRouteTable
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal: '*'
          Action:
            - dynamodb:PutItem
            - dynamodb:GetItem
            - dynamodb:UpdateItem
            - dynamodb:Query
            - dynamodb:Scan
          Resource: 
            - !Sub 'arn:${AWS::Partition}:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${ProjectName}-*'
```

**DNS Name**: Uses route table entries (no specific DNS name)

#### 3. CloudWatch Logs Endpoint

**Purpose**: Send Lambda function logs to CloudWatch

**Configuration:**
```yaml
CloudWatchLogsEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.logs'
    VpcEndpointType: Interface
    SubnetIds:
      - !Ref VPCEndpointSubnet
    SecurityGroupIds:
      - !Ref VPCEndpointSecurityGroup
    PrivateDnsEnabled: true
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal: '*'
          Action:
            - logs:CreateLogGroup
            - logs:CreateLogStream
            - logs:PutLogEvents
            - logs:DescribeLogGroups
            - logs:DescribeLogStreams
          Resource: 
            - !Sub 'arn:${AWS::Partition}:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/lambda/${ProjectName}-*'
```

**DNS Name**: `logs.us-gov-west-1.amazonaws.com`

#### 4. CloudWatch Monitoring Endpoint

**Purpose**: Send custom metrics and monitoring data

**Configuration:**
```yaml
CloudWatchEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.monitoring'
    VpcEndpointType: Interface
    SubnetIds:
      - !Ref VPCEndpointSubnet
    SecurityGroupIds:
      - !Ref VPCEndpointSecurityGroup
    PrivateDnsEnabled: true
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal: '*'
          Action:
            - cloudwatch:PutMetricData
            - cloudwatch:GetMetricStatistics
            - cloudwatch:ListMetrics
          Resource: '*'
```

**DNS Name**: `monitoring.us-gov-west-1.amazonaws.com`

### Deployment Commands

```bash
# Deploy GovCloud VPC endpoints
aws cloudformation deploy \
    --template-file infrastructure/vpn-govcloud-endpoints.yaml \
    --stack-name "${PROJECT_NAME}-govcloud-endpoints-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
        VPCStackName="${PROJECT_NAME}-govcloud-vpc-${ENVIRONMENT}" \
    --capabilities CAPABILITY_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1
```

## Commercial VPC Endpoints

The Commercial partition requires VPC endpoints for receiving cross-partition requests and accessing AWS services.

### Required Endpoints

#### 1. Bedrock Runtime Endpoint

**Purpose**: Provide access to Bedrock AI models from GovCloud

**Configuration:**
```yaml
BedrockEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.bedrock-runtime'
    VpcEndpointType: Interface
    SubnetIds:
      - !Ref VPCEndpointSubnet
    SecurityGroupIds:
      - !Ref VPCEndpointSecurityGroup
    PrivateDnsEnabled: true
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal: '*'
          Action:
            - bedrock:InvokeModel
            - bedrock:InvokeModelWithResponseStream
          Resource: 
            - !Sub 'arn:aws:bedrock:${AWS::Region}::foundation-model/*'
          Condition:
            StringEquals:
              'aws:PrincipalTag:Project': !Ref ProjectName
```

**DNS Name**: `bedrock-runtime.us-east-1.amazonaws.com`

#### 2. CloudWatch Logs Endpoint

**Purpose**: Log cross-partition requests and responses

**Configuration:**
```yaml
CloudWatchLogsEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.logs'
    VpcEndpointType: Interface
    SubnetIds:
      - !Ref VPCEndpointSubnet
    SecurityGroupIds:
      - !Ref VPCEndpointSecurityGroup
    PrivateDnsEnabled: true
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal: '*'
          Action:
            - logs:CreateLogGroup
            - logs:CreateLogStream
            - logs:PutLogEvents
          Resource: 
            - !Sub 'arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/vpn/${ProjectName}-*'
```

**DNS Name**: `logs.us-east-1.amazonaws.com`

#### 3. CloudWatch Monitoring Endpoint

**Purpose**: Monitor VPN performance and health

**Configuration:**
```yaml
CloudWatchEndpoint:
  Type: AWS::EC2::VPCEndpoint
  Properties:
    VpcId: !Ref VPC
    ServiceName: !Sub 'com.amazonaws.${AWS::Region}.monitoring'
    VpcEndpointType: Interface
    SubnetIds:
      - !Ref VPCEndpointSubnet
    SecurityGroupIds:
      - !Ref VPCEndpointSecurityGroup
    PrivateDnsEnabled: true
    PolicyDocument:
      Version: '2012-10-17'
      Statement:
        - Effect: Allow
          Principal: '*'
          Action:
            - cloudwatch:PutMetricData
            - cloudwatch:GetMetricStatistics
          Resource: '*'
```

**DNS Name**: `monitoring.us-east-1.amazonaws.com`

### Deployment Commands

```bash
# Deploy Commercial VPC endpoints
aws cloudformation deploy \
    --template-file infrastructure/vpn-commercial-endpoints.yaml \
    --stack-name "${PROJECT_NAME}-commercial-endpoints-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
        VPCStackName="${PROJECT_NAME}-commercial-vpc-${ENVIRONMENT}" \
    --capabilities CAPABILITY_IAM \
    --profile "$COMMERCIAL_PROFILE" \
    --region us-east-1
```

## Security Configuration

### Security Groups

VPC endpoints require security groups to control access.

#### VPC Endpoint Security Group

```yaml
VPCEndpointSecurityGroup:
  Type: AWS::EC2::SecurityGroup
  Properties:
    GroupDescription: 'Security group for VPC endpoints'
    VpcId: !Ref VPC
    SecurityGroupIngress:
      # Allow HTTPS from Lambda security group
      - IpProtocol: tcp
        FromPort: 443
        ToPort: 443
        SourceSecurityGroupId: !Ref LambdaSecurityGroup
        Description: 'HTTPS from Lambda functions'
      # Allow HTTPS from VPN CIDR (for cross-partition access)
      - IpProtocol: tcp
        FromPort: 443
        ToPort: 443
        CidrIp: '10.0.0.0/16'  # GovCloud VPC CIDR
        Description: 'HTTPS from GovCloud VPC via VPN'
    SecurityGroupEgress:
      # Allow all outbound (default)
      - IpProtocol: -1
        CidrIp: '0.0.0.0/0'
        Description: 'All outbound traffic'
```

#### Lambda Security Group

```yaml
LambdaSecurityGroup:
  Type: AWS::EC2::SecurityGroup
  Properties:
    GroupDescription: 'Security group for Lambda functions'
    VpcId: !Ref VPC
    SecurityGroupEgress:
      # Allow HTTPS to VPC endpoints
      - IpProtocol: tcp
        FromPort: 443
        ToPort: 443
        DestinationSecurityGroupId: !Ref VPCEndpointSecurityGroup
        Description: 'HTTPS to VPC endpoints'
      # Allow all traffic to Commercial VPC via VPN
      - IpProtocol: -1
        CidrIp: '172.16.0.0/16'  # Commercial VPC CIDR
        Description: 'All traffic to Commercial VPC via VPN'
```

### Endpoint Policies

Endpoint policies provide fine-grained access control for VPC endpoints.

#### Least Privilege Policy Example

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws-us-gov:secretsmanager:us-gov-west-1:123456789012:secret:cross-partition-inference-*",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalTag:Project": "cross-partition-inference"
                }
            }
        }
    ]
}
```

## DNS Configuration

### Private DNS

VPC endpoints support private DNS, which allows you to use the standard AWS service DNS names.

**Benefits:**
- No code changes required
- Standard AWS SDK behavior
- Automatic failover to public endpoints if VPC endpoint fails

**Configuration:**
```yaml
PrivateDnsEnabled: true
```

### Custom DNS Names

You can also use the VPC endpoint-specific DNS names:

**Format:** `vpce-{endpoint-id}-{random-string}.{service}.{region}.vpce.amazonaws.com`

**Example:** `vpce-1234567890abcdef0-12345678.secretsmanager.us-gov-west-1.vpce.amazonaws.com`

### DNS Resolution Testing

```bash
# Test DNS resolution from within VPC
nslookup secretsmanager.us-gov-west-1.amazonaws.com

# Test VPC endpoint specific DNS
nslookup vpce-1234567890abcdef0-12345678.secretsmanager.us-gov-west-1.vpce.amazonaws.com

# Test connectivity
nc -zv secretsmanager.us-gov-west-1.amazonaws.com 443
```

## Troubleshooting

### Common Issues

#### 1. DNS Resolution Failures

**Symptoms:**
- Cannot resolve AWS service DNS names
- Connection timeouts to AWS services

**Solutions:**
```bash
# Check VPC DNS settings
aws ec2 describe-vpcs --vpc-ids $GOVCLOUD_VPC_ID \
    --query 'Vpcs[0].{DnsHostnames:DnsHostnames,DnsSupport:DnsSupport}'

# Verify private DNS is enabled
aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$GOVCLOUD_VPC_ID" \
    --query 'VpcEndpoints[*].{Service:ServiceName,PrivateDns:PrivateDnsEnabled}'

# Test DNS resolution
dig secretsmanager.us-gov-west-1.amazonaws.com
```

#### 2. Security Group Issues

**Symptoms:**
- Connection refused errors
- Timeouts when accessing VPC endpoints

**Solutions:**
```bash
# Check security group rules
aws ec2 describe-security-groups \
    --group-ids $VPC_ENDPOINT_SG_ID \
    --query 'SecurityGroups[0].IpPermissions'

# Verify Lambda security group egress rules
aws ec2 describe-security-groups \
    --group-ids $LAMBDA_SG_ID \
    --query 'SecurityGroups[0].IpPermissionsEgress'
```

#### 3. Endpoint Policy Issues

**Symptoms:**
- Access denied errors
- Unauthorized errors when calling AWS services

**Solutions:**
```bash
# Check endpoint policy
aws ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids $ENDPOINT_ID \
    --query 'VpcEndpoints[0].PolicyDocument'

# Verify IAM permissions
aws iam simulate-principal-policy \
    --policy-source-arn $LAMBDA_ROLE_ARN \
    --action-names secretsmanager:GetSecretValue \
    --resource-arns $SECRET_ARN
```

#### 4. Route Table Issues

**Symptoms:**
- Cannot reach gateway endpoints (DynamoDB)
- Routing loops or blackholes

**Solutions:**
```bash
# Check route table entries
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$GOVCLOUD_VPC_ID" \
    --query 'RouteTables[*].Routes'

# Verify gateway endpoint routes
aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$GOVCLOUD_VPC_ID" "Name=vpc-endpoint-type,Values=Gateway" \
    --query 'VpcEndpoints[*].{Service:ServiceName,RouteTableIds:RouteTableIds}'
```

### Diagnostic Commands

```bash
# List all VPC endpoints
aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$GOVCLOUD_VPC_ID" \
    --query 'VpcEndpoints[*].{Service:ServiceName,State:State,Type:VpcEndpointType}'

# Check endpoint network interfaces
aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$GOVCLOUD_VPC_ID" "Name=description,Values=*VPC Endpoint*" \
    --query 'NetworkInterfaces[*].{Id:NetworkInterfaceId,SubnetId:SubnetId,PrivateIp:PrivateIpAddress}'

# Test endpoint connectivity
aws secretsmanager list-secrets --region us-gov-west-1 --max-items 1

# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/VPC-Endpoint \
    --metric-name PacketDropCount \
    --dimensions Name=VPC-Endpoint-Id,Value=$ENDPOINT_ID \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum
```

## Best Practices

### Security

1. **Use Least Privilege Policies**
   - Restrict endpoint policies to specific resources
   - Use condition keys for additional security
   - Regularly review and update policies

2. **Implement Defense in Depth**
   - Use security groups AND endpoint policies
   - Monitor VPC Flow Logs
   - Enable CloudTrail for API calls

3. **Network Segmentation**
   - Use dedicated subnets for VPC endpoints
   - Separate endpoint subnets from application subnets
   - Implement proper routing

### Performance

1. **Multi-AZ Deployment**
   - Deploy endpoints in multiple Availability Zones
   - Use closest endpoint for better performance
   - Implement health checks

2. **Connection Pooling**
   - Reuse connections to VPC endpoints
   - Implement connection caching in Lambda
   - Monitor connection metrics

3. **DNS Caching**
   - Cache DNS resolutions
   - Use private DNS when possible
   - Monitor DNS resolution times

### Cost Optimization

1. **Endpoint Sharing**
   - Share endpoints across multiple applications
   - Use gateway endpoints when available (S3, DynamoDB)
   - Monitor data processing charges

2. **Right-sizing**
   - Monitor endpoint utilization
   - Remove unused endpoints
   - Optimize endpoint placement

3. **Data Transfer Optimization**
   - Minimize cross-AZ data transfer
   - Use compression when appropriate
   - Monitor data transfer costs

### Monitoring

1. **CloudWatch Metrics**
   - Monitor endpoint packet drops
   - Track data processing volumes
   - Set up alarms for failures

2. **VPC Flow Logs**
   - Monitor traffic patterns
   - Identify security issues
   - Troubleshoot connectivity problems

3. **Application Metrics**
   - Track endpoint response times
   - Monitor error rates
   - Measure throughput

## Configuration Validation

Use the provided scripts to validate VPC endpoint configuration:

```bash
# Validate VPC endpoints
./scripts/validate-vpn-connectivity.sh --verbose

# Test endpoint connectivity
source config-vpn.sh
test_vpn_connectivity

# Check endpoint status
aws ec2 describe-vpc-endpoints \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --query 'VpcEndpoints[*].{Service:ServiceName,State:State,DNS:DnsEntries[0].DnsName}'
```

## Next Steps

After configuring VPC endpoints:

1. **Test all endpoint connectivity**
2. **Implement monitoring and alerting**
3. **Document endpoint-specific procedures**
4. **Set up automated health checks**
5. **Create incident response procedures**

For operational procedures, see [VPN-Operations-Guide.md](VPN-Operations-Guide.md).