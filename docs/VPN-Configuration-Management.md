# VPN Configuration Management

This document describes the automatic configuration management system for the VPN connectivity solution.

## Overview

The VPN configuration management system automatically extracts CloudFormation outputs and real-time VPN status to generate configuration files that can be used by deployment scripts, monitoring tools, and operational procedures.

## Components

### 1. VPNConfigManager (`scripts/vpn_config_manager.py`)

The core Python class that handles configuration extraction and generation.

**Features:**
- Extracts CloudFormation stack outputs from both GovCloud and Commercial partitions
- Retrieves real-time VPN tunnel status from AWS APIs
- Generates shell configuration files with all necessary environment variables
- Validates configuration completeness and correctness
- Supports multiple AWS CLI profiles for cross-partition access

**Usage:**
```bash
python3 scripts/vpn_config_manager.py --project-name cross-partition-inference --environment dev
```

### 2. Configuration Extraction Script (`scripts/extract-vpn-config.sh`)

A shell wrapper that provides easy command-line access to the VPNConfigManager.

**Features:**
- Command-line interface with comprehensive options
- Automatic AWS CLI profile validation
- Configuration file generation and validation
- Auto-loading of generated configuration

**Usage:**
```bash
# Extract configuration with defaults
./scripts/extract-vpn-config.sh

# Extract for specific environment
./scripts/extract-vpn-config.sh --environment prod --output-dir ./config

# Validate existing configuration
./scripts/extract-vpn-config.sh --validate-only
```

### 3. VPN Status Monitor (`scripts/get-vpn-status.sh`)

Real-time VPN tunnel status monitoring and testing.

**Features:**
- Real-time VPN tunnel status from both partitions
- VPN Gateway and Customer Gateway status
- Connectivity testing
- Continuous monitoring mode
- Quick status summaries

**Usage:**
```bash
# Show full VPN status
./scripts/get-vpn-status.sh

# Quick summary
./scripts/get-vpn-status.sh summary

# Continuous monitoring
./scripts/get-vpn-status.sh watch

# Test connectivity
./scripts/get-vpn-status.sh test
```

### 4. Integrated Deployment (`scripts/deploy-vpn-with-config.sh`)

Complete deployment with automatic configuration generation.

**Features:**
- Full VPN infrastructure deployment
- Automatic configuration extraction after deployment
- Deployment validation and testing
- Configuration validation and connectivity testing
- Deployment reporting

**Usage:**
```bash
# Deploy and configure
./scripts/deploy-vpn-with-config.sh

# Skip deployment, only generate configuration
./scripts/deploy-vpn-with-config.sh --skip-deployment

# Validate existing deployment
./scripts/deploy-vpn-with-config.sh --validate-only
```

### 5. Configuration Validation (`scripts/validate-vpn-connectivity.sh`)

Comprehensive validation of VPN connectivity and configuration.

**Features:**
- Configuration file validation
- VPN infrastructure validation
- VPN tunnel connectivity testing
- Lambda function configuration validation
- VPC endpoint validation
- Continuous monitoring mode

**Usage:**
```bash
# Run comprehensive validation
./scripts/validate-vpn-connectivity.sh

# Verbose validation
./scripts/validate-vpn-connectivity.sh --verbose

# Continuous monitoring
./scripts/validate-vpn-connectivity.sh --continuous
```

## Generated Configuration Files

### 1. `config-vpn.sh`

The main configuration file containing all environment variables and utility functions.

**Contents:**
- Project and environment configuration
- VPC IDs and CIDR blocks
- VPC endpoint URLs
- VPN connection IDs and tunnel status
- Lambda function configuration
- Monitoring configuration
- Validation and testing functions

**Usage:**
```bash
# Load configuration
source config-vpn.sh

# Validate configuration
validate_vpn_config

# Test connectivity
test_vpn_connectivity

# Show status
show_vpn_status

# Show routing details
show_vpn_routing
```

### 2. `vpn-config-data.json`

Raw configuration data in JSON format for programmatic access.

**Contents:**
- CloudFormation stack outputs
- VPN tunnel status
- Timestamps and metadata

### 3. `vpn-config-validation.json`

Configuration validation results.

**Contents:**
- Validation status (pass/fail)
- Error messages
- Warning messages
- Summary statistics

## Configuration Variables

### Project Configuration
- `PROJECT_NAME`: Project name
- `ENVIRONMENT`: Environment (dev/staging/prod)
- `ROUTING_METHOD`: Always "vpn" for this solution

### VPC Configuration
- `GOVCLOUD_VPC_ID`: GovCloud VPC ID
- `GOVCLOUD_VPC_CIDR`: GovCloud VPC CIDR block
- `GOVCLOUD_PRIVATE_SUBNET_ID`: Private subnet for Lambda
- `GOVCLOUD_VPN_SUBNET_ID`: VPN subnet
- `GOVCLOUD_LAMBDA_SG_ID`: Lambda security group
- `COMMERCIAL_VPC_ID`: Commercial VPC ID
- `COMMERCIAL_VPC_CIDR`: Commercial VPC CIDR block
- `COMMERCIAL_PRIVATE_SUBNET_ID`: Commercial private subnet
- `COMMERCIAL_VPN_SUBNET_ID`: Commercial VPN subnet

### VPC Endpoints
- `VPC_ENDPOINT_SECRETS`: Secrets Manager endpoint
- `VPC_ENDPOINT_DYNAMODB`: DynamoDB endpoint
- `VPC_ENDPOINT_LOGS`: CloudWatch Logs endpoint
- `VPC_ENDPOINT_MONITORING`: CloudWatch Monitoring endpoint
- `COMMERCIAL_BEDROCK_ENDPOINT`: Bedrock endpoint
- `COMMERCIAL_LOGS_ENDPOINT`: Commercial CloudWatch Logs endpoint
- `COMMERCIAL_MONITORING_ENDPOINT`: Commercial CloudWatch Monitoring endpoint

### VPN Configuration
- `GOVCLOUD_VPN_CONNECTION_ID`: GovCloud VPN connection ID
- `GOVCLOUD_VPN_STATE`: GovCloud VPN state
- `GOVCLOUD_VPN_TUNNEL_1_IP`: Primary tunnel IP
- `GOVCLOUD_VPN_TUNNEL_1_STATUS`: Primary tunnel status
- `GOVCLOUD_VPN_TUNNEL_2_IP`: Secondary tunnel IP
- `GOVCLOUD_VPN_TUNNEL_2_STATUS`: Secondary tunnel status
- `COMMERCIAL_VPN_CONNECTION_ID`: Commercial VPN connection ID
- `COMMERCIAL_VPN_STATE`: Commercial VPN state
- `COMMERCIAL_VPN_TUNNEL_1_IP`: Commercial primary tunnel IP
- `COMMERCIAL_VPN_TUNNEL_1_STATUS`: Commercial primary tunnel status
- `COMMERCIAL_VPN_TUNNEL_2_IP`: Commercial secondary tunnel IP
- `COMMERCIAL_VPN_TUNNEL_2_STATUS`: Commercial secondary tunnel status

### Lambda Configuration
- `LAMBDA_FUNCTION_NAME`: Lambda function name
- `LAMBDA_FUNCTION_ARN`: Lambda function ARN
- `LAMBDA_ROLE_ARN`: Lambda execution role ARN
- `COMMERCIAL_CREDENTIALS_SECRET`: Commercial credentials secret name
- `REQUEST_LOG_TABLE`: Request logging DynamoDB table

### Monitoring Configuration
- `CLOUDWATCH_LOG_GROUP`: CloudWatch log group
- `CLOUDWATCH_NAMESPACE`: CloudWatch metrics namespace
- `MONITORING_DASHBOARD_URL`: CloudWatch dashboard URL
- `ALARM_TOPIC_ARN`: SNS topic for alarms

## Network Architecture Visualization

The configuration includes a visual representation of the network architecture:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                GovCloud Partition                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                        VPC (10.0.0.0/16)                               │    │
│  │                                                                         │    │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │    │
│  │  │  Lambda Subnet  │    │  VPC Endpoints  │    │   VPN Subnet    │     │    │
│  │  │   (Private)     │    │    Subnet       │    │                 │     │    │
│  │  │                 │    │                 │    │  ┌───────────┐  │     │    │
│  │  │  ┌───────────┐  │    │  ┌───────────┐  │    │  │    VPN    │  │     │    │
│  │  │  │  Lambda   │  │    │  │ Secrets   │  │    │  │  Gateway  │  │     │    │
│  │  │  │ Function  │  │    │  │ DynamoDB  │  │    │  │           │  │     │    │
│  │  │  │           │  │    │  │CloudWatch │  │    │  └───────────┘  │     │    │
│  │  │  └───────────┘  │    │  └───────────┘  │    │                 │     │    │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘     │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
                                       │
                                   VPN Tunnel
                                       │
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Commercial Partition                               │
│  ┌─────────────────────────────────────────────────────────────────────────┐    │
│  │                      VPC (172.16.0.0/16)                               │    │
│  │                                                                         │    │
│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │    │
│  │  │   VPN Subnet    │    │  VPC Endpoints  │    │  Private Subnet │     │    │
│  │  │                 │    │    Subnet       │    │   (Reserved)    │     │    │
│  │  │  ┌───────────┐  │    │                 │    │                 │     │    │
│  │  │  │    VPN    │  │    │  ┌───────────┐  │    │                 │     │    │
│  │  │  │  Gateway  │  │    │  │  Bedrock  │  │    │                 │     │    │
│  │  │  │           │  │    │  │CloudWatch │  │    │                 │     │    │
│  │  │  └───────────┘  │    │  └───────────┘  │    │                 │     │    │
│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘     │    │
│  └─────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Traffic Flow

1. **Lambda Function Start**: Lambda function starts in GovCloud private subnet
2. **Local AWS Services**: Accesses local AWS services via VPC endpoints (no internet)
3. **Cross-Partition Routing**: For Bedrock requests, routes through VPN tunnel to Commercial
4. **Commercial VPC**: Commercial VPC receives traffic via VPN gateway
5. **Bedrock Access**: Traffic reaches Bedrock via Commercial VPC endpoint
6. **Response Return**: Response returns via same VPN path

## Security Features

- **Complete Network Isolation**: No internet gateways in either VPC
- **VPC Endpoint Access**: All AWS service access via VPC endpoints
- **IPSec Encryption**: Cross-partition traffic encrypted with IPSec
- **Security Groups**: Restrict traffic to necessary ports only
- **Network ACLs**: Additional traffic filtering layer
- **VPC Flow Logs**: Capture all network traffic for monitoring

## Redundancy and High Availability

- **Dual VPN Tunnels**: Two tunnels per connection for high availability
- **BGP Routing**: Automatic failover between tunnels
- **Multiple Availability Zones**: Resources deployed across multiple AZs where supported

## Operational Procedures

### Daily Operations

1. **Check VPN Status**:
   ```bash
   ./scripts/get-vpn-status.sh summary
   ```

2. **Validate Configuration**:
   ```bash
   source config-vpn.sh
   validate_vpn_config
   ```

3. **Test Connectivity**:
   ```bash
   test_vpn_connectivity
   ```

### Troubleshooting

1. **VPN Tunnel Down**:
   ```bash
   # Check tunnel status
   ./scripts/get-vpn-status.sh
   
   # Check AWS console for tunnel details
   # Verify BGP routing
   # Check security group rules
   ```

2. **Configuration Issues**:
   ```bash
   # Re-extract configuration
   ./scripts/extract-vpn-config.sh
   
   # Validate configuration
   ./scripts/validate-vpn-connectivity.sh --verbose
   ```

3. **Lambda Function Issues**:
   ```bash
   # Check Lambda VPC configuration
   aws lambda get-function-configuration --function-name $LAMBDA_FUNCTION_NAME
   
   # Check Lambda logs
   aws logs tail $CLOUDWATCH_LOG_GROUP --follow
   ```

### Monitoring

1. **Continuous Monitoring**:
   ```bash
   # Monitor VPN status
   ./scripts/get-vpn-status.sh watch
   
   # Monitor configuration
   ./scripts/validate-vpn-connectivity.sh --continuous
   ```

2. **CloudWatch Dashboard**:
   ```bash
   # Open monitoring dashboard
   echo $MONITORING_DASHBOARD_URL
   ```

## Example Configuration Template

See `config/config-vpn-example.sh` for a complete example of what the generated configuration looks like.

## Integration with Deployment

The configuration management system is fully integrated with the deployment process:

1. **Automatic Generation**: Configuration is automatically generated after successful deployment
2. **Validation**: Configuration is validated as part of the deployment process
3. **Auto-Loading**: Configuration is automatically loaded for immediate use
4. **Reporting**: Deployment reports include configuration status

This ensures that the configuration is always up-to-date and reflects the actual deployed infrastructure.