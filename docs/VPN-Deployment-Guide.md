# VPN Connectivity Solution - Deployment Guide

This guide provides step-by-step instructions for deploying the VPN connectivity solution for cross-partition AI inference between AWS GovCloud and Commercial partitions.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Setup](#pre-deployment-setup)
3. [Deployment Options](#deployment-options)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Post-Deployment Configuration](#post-deployment-configuration)
6. [Validation and Testing](#validation-and-testing)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

### AWS Account Requirements

- **GovCloud Account**: AWS GovCloud account with appropriate permissions
- **Commercial Account**: AWS Commercial account with appropriate permissions
- **Cross-Account Access**: If using separate accounts, ensure proper cross-account IAM roles

### Required Permissions

#### GovCloud Partition Permissions
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "lambda:*",
                "iam:*",
                "cloudformation:*",
                "secretsmanager:*",
                "dynamodb:*",
                "logs:*",
                "cloudwatch:*",
                "sns:*",
                "s3:*"
            ],
            "Resource": "*"
        }
    ]
}
```

#### Commercial Partition Permissions
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "cloudformation:*",
                "bedrock:*",
                "logs:*",
                "cloudwatch:*",
                "sns:*",
                "s3:*"
            ],
            "Resource": "*"
        }
    ]
}
```

### Software Requirements

- **AWS CLI**: Version 2.0 or later
- **Python**: Version 3.8 or later
- **Boto3**: Latest version
- **jq**: JSON processor for shell scripts
- **nc (netcat)**: For connectivity testing
- **Git**: For cloning the repository

### Network Requirements

- **Static IP Addresses**: Two static IP addresses for Customer Gateways
- **BGP ASN**: Unique BGP ASN numbers for each partition (if using BGP)
- **Firewall Rules**: Allow IPSec traffic (UDP 500, UDP 4500, ESP protocol 50)

## Pre-Deployment Setup

### 1. Configure AWS CLI Profiles

Set up AWS CLI profiles for both partitions:

```bash
# Configure GovCloud profile
aws configure --profile govcloud
# AWS Access Key ID: [Your GovCloud Access Key]
# AWS Secret Access Key: [Your GovCloud Secret Key]
# Default region name: us-gov-west-1
# Default output format: json

# Configure Commercial profile
aws configure --profile commercial
# AWS Access Key ID: [Your Commercial Access Key]
# AWS Secret Access Key: [Your Commercial Secret Key]
# Default region name: us-east-1
# Default output format: json
```

### 2. Verify AWS CLI Access

Test access to both partitions:

```bash
# Test GovCloud access
aws sts get-caller-identity --profile govcloud

# Test Commercial access
aws sts get-caller-identity --profile commercial
```

### 3. Clone Repository

```bash
git clone <repository-url>
cd cross-partition-inferencing
```

### 4. Install Python Dependencies

```bash
pip3 install boto3 jq
```

### 5. Set Environment Variables

```bash
export PROJECT_NAME="cross-partition-inference"
export ENVIRONMENT="dev"  # or "staging", "prod"
export GOVCLOUD_PROFILE="govcloud"
export COMMERCIAL_PROFILE="commercial"
```

## Deployment Options

### Option 1: Complete Automated Deployment (Recommended)

Deploy everything in one command with automatic configuration:

```bash
./scripts/deploy-vpn-with-config.sh \
    --project-name "$PROJECT_NAME" \
    --environment "$ENVIRONMENT" \
    --govcloud-profile "$GOVCLOUD_PROFILE" \
    --commercial-profile "$COMMERCIAL_PROFILE"
```

### Option 2: Phase-by-Phase Deployment

Deploy infrastructure in phases for better control:

```bash
# Deploy VPC infrastructure
./scripts/deploy-complete-vpn-solution.sh --phase vpc

# Deploy VPC endpoints
./scripts/deploy-complete-vpn-solution.sh --phase endpoints

# Deploy VPN gateways
./scripts/deploy-complete-vpn-solution.sh --phase vpn

# Deploy Lambda functions
./scripts/deploy-complete-vpn-solution.sh --phase lambda

# Deploy security controls
./scripts/deploy-complete-vpn-solution.sh --phase security

# Deploy monitoring
./scripts/deploy-complete-vpn-solution.sh --phase monitoring
```

### Option 3: Manual CloudFormation Deployment

Deploy individual CloudFormation templates manually for maximum control.

## Step-by-Step Deployment

### Step 1: Deploy VPC Infrastructure

The VPC infrastructure creates the foundation for the VPN connectivity solution.

```bash
# Deploy GovCloud VPC
aws cloudformation deploy \
    --template-file infrastructure/vpn-govcloud-vpc.yaml \
    --stack-name "${PROJECT_NAME}-govcloud-vpc-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
    --capabilities CAPABILITY_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Deploy Commercial VPC
aws cloudformation deploy \
    --template-file infrastructure/vpn-commercial-vpc.yaml \
    --stack-name "${PROJECT_NAME}-commercial-vpc-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
    --capabilities CAPABILITY_IAM \
    --profile "$COMMERCIAL_PROFILE" \
    --region us-east-1
```

**What gets deployed:**
- VPC with private subnets (no internet gateways)
- Security groups for Lambda, VPC endpoints, and VPN
- Network ACLs for additional security
- Route tables configured for VPN routing

### Step 2: Deploy VPC Endpoints

VPC endpoints eliminate the need for NAT gateways and provide secure access to AWS services.

```bash
# Deploy GovCloud VPC Endpoints
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

# Deploy Commercial VPC Endpoints
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

**What gets deployed:**
- **GovCloud**: Secrets Manager, DynamoDB, CloudWatch Logs, CloudWatch Metrics endpoints
- **Commercial**: Bedrock, CloudWatch Logs, CloudWatch Metrics endpoints
- Security groups allowing HTTPS access from Lambda functions
- Endpoint policies for least privilege access

### Step 3: Deploy VPN Gateways

VPN gateways establish the encrypted connection between partitions.

```bash
# Deploy GovCloud VPN Gateway
aws cloudformation deploy \
    --template-file infrastructure/vpn-gateway.yaml \
    --stack-name "${PROJECT_NAME}-govcloud-vpn-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
        VPCStackName="${PROJECT_NAME}-govcloud-vpc-${ENVIRONMENT}" \
        CustomerGatewayIP="203.0.113.1" \
        RemoteVPCCIDR="172.16.0.0/16" \
        Tunnel1PreSharedKey="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)" \
        Tunnel2PreSharedKey="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)" \
    --capabilities CAPABILITY_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Deploy Commercial VPN Gateway
aws cloudformation deploy \
    --template-file infrastructure/vpn-gateway.yaml \
    --stack-name "${PROJECT_NAME}-commercial-vpn-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
        VPCStackName="${PROJECT_NAME}-commercial-vpc-${ENVIRONMENT}" \
        CustomerGatewayIP="203.0.113.2" \
        RemoteVPCCIDR="10.0.0.0/16" \
        Tunnel1PreSharedKey="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)" \
        Tunnel2PreSharedKey="$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)" \
    --capabilities CAPABILITY_IAM \
    --profile "$COMMERCIAL_PROFILE" \
    --region us-east-1
```

**What gets deployed:**
- VPN Gateways in both partitions
- Customer Gateways with specified IP addresses
- Site-to-Site VPN connections with redundant tunnels
- BGP routing configuration for automatic failover

**Important Notes:**
- Replace `203.0.113.1` and `203.0.113.2` with your actual static IP addresses
- Pre-shared keys are generated automatically for security
- VPN tunnels may take 5-10 minutes to establish

### Step 4: Deploy Lambda Functions

Lambda functions handle the cross-partition AI inference requests.

```bash
# Deploy Lambda function in GovCloud
aws cloudformation deploy \
    --template-file infrastructure/vpn-lambda-function.yaml \
    --stack-name "${PROJECT_NAME}-govcloud-lambda-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
        VPCStackName="${PROJECT_NAME}-govcloud-vpc-${ENVIRONMENT}" \
        VPCEndpointsStackName="${PROJECT_NAME}-govcloud-endpoints-${ENVIRONMENT}" \
        CommercialBedrockEndpoint="vpce-xxx.bedrock-runtime.us-east-1.vpce.amazonaws.com" \
        CommercialCredentialsSecret="${PROJECT_NAME}-commercial-credentials-${ENVIRONMENT}" \
    --capabilities CAPABILITY_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1
```

**What gets deployed:**
- Lambda function configured for VPC deployment
- Lambda execution role with necessary permissions
- Environment variables for VPC endpoints and cross-partition access
- DynamoDB table for request logging

### Step 5: Deploy Security Controls

Security controls provide additional monitoring and compliance features.

```bash
# Deploy security controls
aws cloudformation deploy \
    --template-file infrastructure/vpn-security-controls.yaml \
    --stack-name "${PROJECT_NAME}-govcloud-security-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
        VPCStackName="${PROJECT_NAME}-govcloud-vpc-${ENVIRONMENT}" \
        VPNStackName="${PROJECT_NAME}-govcloud-vpn-${ENVIRONMENT}" \
    --capabilities CAPABILITY_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Deploy audit and compliance
aws cloudformation deploy \
    --template-file infrastructure/vpn-audit-compliance.yaml \
    --stack-name "${PROJECT_NAME}-govcloud-audit-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
    --capabilities CAPABILITY_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1
```

**What gets deployed:**
- VPC Flow Logs for network traffic monitoring
- CloudTrail for API call auditing
- Config rules for compliance monitoring
- S3 buckets for log storage with encryption

### Step 6: Deploy Monitoring and Alerting

Monitoring provides visibility into VPN health and performance.

```bash
# Deploy GovCloud monitoring
aws cloudformation deploy \
    --template-file infrastructure/vpn-monitoring-alerting.yaml \
    --stack-name "${PROJECT_NAME}-govcloud-monitoring-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
        AlertEmail="admin@example.com" \
        LambdaFunctionName="${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}" \
    --capabilities CAPABILITY_IAM \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Deploy Commercial monitoring
aws cloudformation deploy \
    --template-file infrastructure/vpn-monitoring-alerting.yaml \
    --stack-name "${PROJECT_NAME}-commercial-monitoring-${ENVIRONMENT}" \
    --parameter-overrides \
        ProjectName="$PROJECT_NAME" \
        Environment="$ENVIRONMENT" \
        AlertEmail="admin@example.com" \
    --capabilities CAPABILITY_IAM \
    --profile "$COMMERCIAL_PROFILE" \
    --region us-east-1
```

**What gets deployed:**
- CloudWatch dashboards for VPN metrics
- CloudWatch alarms for critical conditions
- SNS topics for alert notifications
- Custom metrics for application performance

## Post-Deployment Configuration

### 1. Extract Configuration

After successful deployment, extract the configuration:

```bash
./scripts/extract-vpn-config.sh \
    --project-name "$PROJECT_NAME" \
    --environment "$ENVIRONMENT" \
    --govcloud-profile "$GOVCLOUD_PROFILE" \
    --commercial-profile "$COMMERCIAL_PROFILE"
```

This generates:
- `config-vpn.sh`: Main configuration file
- `vpn-config-data.json`: Raw configuration data
- `vpn-config-validation.json`: Validation results

### 2. Load Configuration

```bash
# Load the configuration
source config-vpn.sh

# Verify configuration is loaded
echo "Project: $PROJECT_NAME"
echo "GovCloud VPC: $GOVCLOUD_VPC_ID"
echo "Commercial VPC: $COMMERCIAL_VPC_ID"
```

### 3. Set Up Commercial Credentials

Create credentials for accessing Commercial partition services:

```bash
# Create commercial credentials secret
aws secretsmanager create-secret \
    --name "$COMMERCIAL_CREDENTIALS_SECRET" \
    --description "Commercial partition credentials for cross-partition access" \
    --secret-string '{
        "access_key_id": "AKIA...",
        "secret_access_key": "...",
        "region": "us-east-1"
    }' \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1
```

## Validation and Testing

### 1. Validate Configuration

```bash
# Run comprehensive validation
./scripts/validate-vpn-connectivity.sh --verbose

# Or use the configuration function
validate_vpn_config
```

### 2. Test VPN Connectivity

```bash
# Test VPN tunnel status
./scripts/get-vpn-status.sh

# Test connectivity
test_vpn_connectivity

# Show VPN status
show_vpn_status
```

### 3. Test Lambda Function

```bash
# Test the Lambda function
aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --payload '{
        "model_id": "anthropic.claude-3-sonnet-20240229-v1:0",
        "prompt": "Hello, this is a test of cross-partition connectivity.",
        "max_tokens": 100
    }' \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    response.json

# Check the response
cat response.json | jq '.'
```

### 4. Monitor VPN Health

```bash
# Continuous monitoring
./scripts/get-vpn-status.sh watch

# Check CloudWatch dashboard
echo "$MONITORING_DASHBOARD_URL"
```

## Troubleshooting

### Common Issues

#### 1. VPN Tunnels Not Establishing

**Symptoms:**
- VPN connection state is "available" but tunnels show "DOWN"
- No traffic flowing between partitions

**Solutions:**
```bash
# Check VPN tunnel status
aws ec2 describe-vpn-connections \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Verify Customer Gateway IP addresses
# Check firewall rules for IPSec traffic
# Verify pre-shared keys match
# Check BGP configuration
```

#### 2. Lambda Function VPC Configuration Issues

**Symptoms:**
- Lambda function timeouts
- Cannot reach VPC endpoints
- DNS resolution failures

**Solutions:**
```bash
# Check Lambda VPC configuration
aws lambda get-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Verify security group rules
# Check subnet routing tables
# Verify VPC endpoint DNS resolution
```

#### 3. Cross-Partition Authentication Issues

**Symptoms:**
- Access denied errors when calling Bedrock
- Invalid credentials errors

**Solutions:**
```bash
# Check commercial credentials secret
aws secretsmanager get-secret-value \
    --secret-id "$COMMERCIAL_CREDENTIALS_SECRET" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Verify IAM permissions in Commercial account
# Check credential rotation
```

#### 4. VPC Endpoint Connectivity Issues

**Symptoms:**
- Cannot reach AWS services
- DNS resolution failures for VPC endpoints

**Solutions:**
```bash
# Check VPC endpoint status
aws ec2 describe-vpc-endpoints \
    --filters "Name=tag:Project,Values=$PROJECT_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Verify security group rules
# Check route table associations
# Test DNS resolution
```

### Diagnostic Commands

```bash
# Check all VPN connections
./scripts/get-vpn-status.sh

# Validate entire configuration
./scripts/validate-vpn-connectivity.sh --verbose

# Check Lambda logs
aws logs tail "$CLOUDWATCH_LOG_GROUP" --follow \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Check VPC Flow Logs
aws logs describe-log-groups \
    --log-group-name-prefix "/aws/vpc/flowlogs" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1
```

### Getting Help

1. **Check CloudWatch Logs**: All components log to CloudWatch
2. **Review CloudFormation Events**: Check stack events for deployment issues
3. **Use Validation Scripts**: Run comprehensive validation scripts
4. **Check AWS Service Health**: Verify AWS service status
5. **Review Security Groups**: Ensure proper network access rules

## Best Practices

### Security
- Use least privilege IAM policies
- Rotate credentials regularly
- Monitor VPC Flow Logs
- Enable CloudTrail logging
- Use encryption in transit and at rest

### Performance
- Monitor VPN tunnel latency
- Use connection pooling in Lambda
- Cache frequently accessed data
- Monitor Lambda cold starts
- Optimize payload sizes

### Cost Optimization
- Monitor VPN data transfer costs
- Use VPC endpoint sharing
- Right-size Lambda memory allocation
- Implement lifecycle policies for logs
- Monitor unused resources

### Operational Excellence
- Automate deployments
- Use infrastructure as code
- Implement comprehensive monitoring
- Create operational runbooks
- Test disaster recovery procedures

## Next Steps

After successful deployment:

1. **Set up monitoring dashboards**
2. **Create operational procedures**
3. **Implement backup and disaster recovery**
4. **Set up automated testing**
5. **Create user documentation**

For detailed operational procedures, see [VPN-Operations-Guide.md](VPN-Operations-Guide.md).