# VPN Tunnel Configuration Summary

## Overview
This document provides the configuration details for establishing VPN tunnels between AWS GovCloud and Commercial AWS for the dual routing API Gateway system.

## GovCloud VPN Configuration

**VPN Connection ID:** vpn-031cfaeb996f62462
**VPN Gateway ID:** vgw-0ff3d67133a602ce9
**Customer Gateway ID:** cgw-027869864badb0474
**State:** available

### Tunnel 1 Configuration
- **GovCloud VPN Gateway Outside IP:** 15.200.132.106
- **GovCloud VPN Gateway Inside IP:** 169.254.193.129
- **Customer Gateway Outside IP:** 203.0.113.12
- **Customer Gateway Inside IP:** 169.254.193.130
- **Pre-shared Key:** E9oMMrDgiQK9abT6tQWOwq4ahMQrDZnF
- **Status:** DOWN

### Tunnel 2 Configuration
- **GovCloud VPN Gateway Outside IP:** 56.137.42.243
- **GovCloud VPN Gateway Inside IP:** 169.254.67.21
- **Customer Gateway Outside IP:** 203.0.113.12
- **Customer Gateway Inside IP:** 169.254.67.22
- **Pre-shared Key:** Tt6eQxek8cJfOgvtS8QJAe0uFBLgiPy_
- **Status:** DOWN

## Commercial AWS Setup Required

### 1. Create Customer Gateway
Create a customer gateway in Commercial AWS pointing to the GovCloud VPN Gateway:
- **IP Address:** 15.200.132.106 (or 56.137.42.243)
- **BGP ASN:** 65000
- **Routing:** Static

### 2. Create VPN Connection
Create a VPN connection in Commercial AWS:
- **Customer Gateway:** Use the customer gateway created above
- **VPN Gateway:** Create or use existing VPN gateway in Commercial AWS
- **Routing:** Configure static routes to GovCloud VPC CIDR

### 3. Configure Route Tables
Update route tables in Commercial AWS to route GovCloud traffic through the VPN connection.

### 4. Security Groups
Ensure security groups allow traffic between GovCloud and Commercial AWS:
- **GovCloud Lambda:** Allow outbound HTTPS (443) to Commercial AWS
- **Commercial Bedrock:** Allow inbound HTTPS (443) from GovCloud

## Network Configuration

### IP Addressing
- **GovCloud VPC CIDR:** 10.0.0.0/16 (adjust as needed)
- **Commercial VPC CIDR:** Configure as needed
- **Tunnel Inside Networks:** 
  - Tunnel 1: 169.254.193.128/30
  - Tunnel 2: 169.254.67.20/30

### Routing
- **GovCloud → Commercial:** Route Commercial AWS CIDRs via VPN Gateway
- **Commercial → GovCloud:** Route GovCloud VPC CIDR via VPN Gateway

## Testing VPN Connectivity

### From GovCloud
```bash
# Test connectivity to Commercial AWS Bedrock endpoint
curl -v https://bedrock-runtime.us-east-1.amazonaws.com/

# Test from Lambda function
aws lambda invoke --function-name dual-routing-api-gateway-prod-vpn-lambda \
  --payload '{"httpMethod": "GET", "path": "/vpn/health"}' response.json
```

### Monitoring
- **CloudWatch Metrics:** Monitor VPN tunnel state and traffic
- **VPC Flow Logs:** Enable flow logs to monitor traffic patterns
- **Lambda Logs:** Check Lambda function logs for connectivity issues

## Troubleshooting

### Common Issues
1. **Tunnels DOWN:** Check customer gateway configuration in Commercial AWS
2. **Routing Issues:** Verify route table configurations in both partitions
3. **Security Groups:** Ensure proper security group rules
4. **DNS Resolution:** Verify DNS resolution for Bedrock endpoints

### Validation Commands
```bash
# Check VPN connection status
aws ec2 describe-vpn-connections --vpn-connection-ids vpn-031cfaeb996f62462

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<vpc-id>"

# Test Lambda function
./scripts/test-vpn-lambda-deployment.sh
```

## Next Steps
1. Deploy Commercial AWS infrastructure using provided CloudFormation template
2. Configure routing in both partitions
3. Test connectivity end-to-end
4. Monitor and optimize performance
