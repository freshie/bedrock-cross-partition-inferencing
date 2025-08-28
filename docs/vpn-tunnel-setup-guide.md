# VPN Tunnel Setup Guide

## 🎯 **Overview**

This guide provides step-by-step instructions for configuring VPN tunnels between AWS GovCloud and Commercial AWS to enable the dual routing API Gateway system.

## 📋 **Prerequisites**

- ✅ GovCloud VPN infrastructure deployed (`dual-routing-api-gateway-prod-vpn-infrastructure`)
- ✅ VPN Lambda function deployed (`dual-routing-api-gateway-prod-vpn-lambda`)
- ✅ AWS CLI configured for both GovCloud and Commercial AWS
- ✅ Appropriate IAM permissions in both partitions

## 🏗️ **Current Infrastructure Status**

### GovCloud (Deployed)
- **VPN Connection ID**: `vpn-031cfaeb996f62462`
- **VPN Gateway ID**: `vgw-0ff3d67133a602ce9`
- **Customer Gateway ID**: `cgw-027869864badb0474`
- **State**: Available
- **Tunnel Status**: Both DOWN (expected until Commercial AWS is configured)

### Commercial AWS (Needs Deployment)
- **Status**: Not deployed
- **Required**: Customer gateway, VPN gateway, VPN connection
- **Configuration Files**: Generated in `config/vpn-tunnels/`

## 🔧 **Step 1: Deploy Commercial AWS Infrastructure**

### Option A: Using CloudFormation Template (Recommended)

1. **Navigate to configuration directory**:
   ```bash
   cd config/vpn-tunnels/
   ```

2. **Review the CloudFormation template**:
   ```bash
   cat commercial-customer-gateway.yaml
   ```

3. **Update the deployment script**:
   ```bash
   # Edit deploy-commercial-vpn.sh
   # Set COMMERCIAL_VPC_ID to your Commercial AWS VPC ID
   vim deploy-commercial-vpn.sh
   ```

4. **Deploy the infrastructure**:
   ```bash
   # Run in Commercial AWS environment
   ./deploy-commercial-vpn.sh
   ```

### Option B: Manual AWS Console Setup

1. **Create Customer Gateway in Commercial AWS**:
   - Go to VPC Console → Customer Gateways
   - Click "Create Customer Gateway"
   - **Name**: `dual-routing-api-gateway-prod-govcloud-cgw`
   - **BGP ASN**: `65000`
   - **IP Address**: `15.200.132.106` (GovCloud VPN Gateway IP)
   - **Certificate ARN**: Leave blank
   - Click "Create Customer Gateway"

2. **Create VPN Gateway in Commercial AWS**:
   - Go to VPC Console → Virtual Private Gateways
   - Click "Create Virtual Private Gateway"
   - **Name**: `dual-routing-api-gateway-prod-commercial-vgw`
   - **ASN**: `Amazon default ASN`
   - Click "Create Virtual Private Gateway"

3. **Attach VPN Gateway to VPC**:
   - Select the created VPN Gateway
   - Actions → Attach to VPC
   - Select your Commercial AWS VPC
   - Click "Attach to VPC"

4. **Create VPN Connection**:
   - Go to VPC Console → Site-to-Site VPN Connections
   - Click "Create VPN Connection"
   - **Name**: `dual-routing-api-gateway-prod-govcloud-vpn`
   - **Target Gateway Type**: Virtual Private Gateway
   - **Virtual Private Gateway**: Select created VPN Gateway
   - **Customer Gateway**: Select created Customer Gateway
   - **Routing Options**: Static
   - **Static IP Prefixes**: `10.0.0.0/16` (GovCloud VPC CIDR)
   - Click "Create VPN Connection"

## 🔧 **Step 2: Configure Routing**

### GovCloud Routing (Already Configured)
The GovCloud routing is already configured through the infrastructure deployment:
- Routes to Commercial AWS CIDRs via VPN Gateway
- Private subnets route through VPN Gateway

### Commercial AWS Routing (Manual Configuration Required)

1. **Update Route Tables**:
   ```bash
   # Get route table ID for your Commercial VPC
   aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<your-commercial-vpc-id>"
   
   # Add route to GovCloud VPC
   aws ec2 create-route \
     --route-table-id <route-table-id> \
     --destination-cidr-block 10.0.0.0/16 \
     --gateway-id <vpn-gateway-id>
   ```

2. **Enable Route Propagation**:
   ```bash
   # Enable route propagation for VPN Gateway
   aws ec2 enable-vgw-route-propagation \
     --route-table-id <route-table-id> \
     --gateway-id <vpn-gateway-id>
   ```

## 🔧 **Step 3: Configure Security Groups**

### GovCloud Security Groups (Already Configured)
The Lambda security group is already configured to allow:
- Outbound HTTPS (443) to all destinations
- Outbound HTTP (80) for health checks
- VPC endpoint connectivity

### Commercial AWS Security Groups (Manual Configuration Required)

1. **Create or Update Security Group for Bedrock Access**:
   ```bash
   # Create security group for Bedrock access
   aws ec2 create-security-group \
     --group-name dual-routing-bedrock-access \
     --description "Allow access from GovCloud Lambda via VPN" \
     --vpc-id <commercial-vpc-id>
   
   # Add inbound rule for HTTPS from GovCloud VPC
   aws ec2 authorize-security-group-ingress \
     --group-id <security-group-id> \
     --protocol tcp \
     --port 443 \
     --cidr 10.0.0.0/16
   ```

## 🔧 **Step 4: Test VPN Connectivity**

### 1. Check Tunnel Status
```bash
# Run from GovCloud environment
AWS_PROFILE=govcloud ./scripts/test-vpn-tunnel-connectivity.sh --tunnel-only
```

### 2. Test Lambda Connectivity
```bash
# Test Lambda function
AWS_PROFILE=govcloud ./scripts/test-vpn-tunnel-connectivity.sh --lambda-only
```

### 3. Test End-to-End Connectivity
```bash
# Full connectivity test
AWS_PROFILE=govcloud ./scripts/test-vpn-tunnel-connectivity.sh
```

### 4. Test Bedrock API Calls
```bash
# Test actual Bedrock API calls
AWS_PROFILE=govcloud ./scripts/test-vpn-tunnel-connectivity.sh --bedrock-test
```

## 🔧 **Step 5: Validate Configuration**

### Expected Results After Successful Setup

1. **VPN Tunnel Status**: At least one tunnel should be UP
   ```bash
   aws --profile govcloud ec2 describe-vpn-connections \
     --vpn-connection-ids vpn-031cfaeb996f62462 \
     --query 'VpnConnections[0].VgwTelemetry[].Status'
   ```

2. **Lambda Function Response**: Should return 200 for valid requests
   ```bash
   aws --profile govcloud lambda invoke \
     --function-name dual-routing-api-gateway-prod-vpn-lambda \
     --payload '{"httpMethod": "POST", "path": "/vpn/model/test", "body": "{\"modelId\": \"test\"}"}' \
     response.json
   ```

3. **Network Connectivity**: Should reach Commercial AWS Bedrock
   ```bash
   # From Lambda function logs, you should see successful connections
   aws --profile govcloud logs filter-log-events \
     --log-group-name /aws/lambda/dual-routing-api-gateway-prod-vpn-lambda \
     --start-time $(date -d '1 hour ago' +%s)000
   ```

## 🔧 **Step 6: Monitor and Troubleshoot**

### Monitoring Commands

1. **VPN Connection Status**:
   ```bash
   # GovCloud
   aws --profile govcloud ec2 describe-vpn-connections \
     --vpn-connection-ids vpn-031cfaeb996f62462
   
   # Commercial AWS (after deployment)
   aws --profile default ec2 describe-vpn-connections
   ```

2. **Route Tables**:
   ```bash
   # Check routing configuration
   aws --profile govcloud ec2 describe-route-tables \
     --filters "Name=vpc-id,Values=vpc-0a82778bbc7b700ef"
   ```

3. **Lambda Function Logs**:
   ```bash
   aws --profile govcloud logs tail /aws/lambda/dual-routing-api-gateway-prod-vpn-lambda --follow
   ```

### Common Issues and Solutions

| Issue | Symptoms | Solution |
|-------|----------|----------|
| **Tunnels DOWN** | Both tunnels show DOWN status | Deploy Commercial AWS infrastructure |
| **502/503 Errors** | Lambda returns service errors | Check VPN tunnel status and routing |
| **401/403 Errors** | Authentication failures | Update bearer token in Secrets Manager |
| **Timeout Errors** | Requests timeout | Check security groups and routing |
| **DNS Resolution** | Cannot resolve endpoints | Check VPC DNS settings |

### Troubleshooting Commands

1. **Test Network Connectivity from Lambda**:
   ```bash
   # Create test payload for network debugging
   cat > test-payload.json << EOF
   {
     "httpMethod": "GET",
     "path": "/vpn/health",
     "headers": {"Content-Type": "application/json"}
   }
   EOF
   
   aws --profile govcloud lambda invoke \
     --function-name dual-routing-api-gateway-prod-vpn-lambda \
     --payload file://test-payload.json \
     response.json && cat response.json
   ```

2. **Check VPC Flow Logs** (if enabled):
   ```bash
   aws --profile govcloud ec2 describe-flow-logs \
     --filter "Name=resource-id,Values=vpc-0a82778bbc7b700ef"
   ```

3. **Validate Security Groups**:
   ```bash
   aws --profile govcloud ec2 describe-security-groups \
     --group-ids sg-0959a4d69ef704c36
   ```

## 🎯 **Success Criteria**

Your VPN tunnel configuration is successful when:

- ✅ **At least one VPN tunnel is UP** in both GovCloud and Commercial AWS
- ✅ **Lambda function responds with 200** for valid VPN requests
- ✅ **Network connectivity test passes** from Lambda to Commercial AWS
- ✅ **Bedrock API calls succeed** through the VPN tunnel
- ✅ **End-to-end dual routing works** for cross-partition requests

## 📊 **Performance Optimization**

### Recommended Settings

1. **Lambda Configuration**:
   - Memory: 512MB (current)
   - Timeout: 30s (current)
   - Reserved Concurrency: 100 (current)

2. **VPN Tunnel Optimization**:
   - Use both tunnels for redundancy
   - Monitor tunnel health and failover
   - Configure appropriate MTU sizes

3. **Monitoring**:
   - Enable VPC Flow Logs
   - Set up CloudWatch alarms for tunnel status
   - Monitor Lambda function metrics

## 🔄 **Next Steps After VPN Setup**

1. **Deploy API Gateway** (optional):
   ```bash
   AWS_PROFILE=govcloud ./scripts/deploy-dual-routing-api-gateway.sh --environment prod
   ```

2. **Set up Monitoring**:
   ```bash
   AWS_PROFILE=govcloud ./scripts/deploy-dual-routing-monitoring.sh --environment prod
   ```

3. **Run Performance Tests**:
   ```bash
   AWS_PROFILE=govcloud ./scripts/run-performance-comparison.sh
   ```

4. **Configure Load Testing**:
   ```bash
   AWS_PROFILE=govcloud ./scripts/run-load-testing.sh --routing-method vpn
   ```

## 📞 **Support and Resources**

- **Configuration Files**: `config/vpn-tunnels/`
- **Test Scripts**: `scripts/test-vpn-tunnel-connectivity.sh`
- **Logs**: `outputs/vpn-*-test-*.txt`
- **CloudFormation Templates**: `infrastructure/dual-routing-vpn-*.yaml`

For additional support, review the generated test reports and CloudWatch logs for detailed error information.