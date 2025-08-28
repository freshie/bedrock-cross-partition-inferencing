# VPN Tunnel Configuration - Quick Reference

## 🚀 **Quick Setup Commands**

### 1. Check Current Status
```bash
AWS_PROFILE=govcloud ./scripts/test-vpn-tunnel-connectivity.sh --tunnel-only
```

### 2. Deploy Commercial AWS Infrastructure
```bash
cd configs/vpn-tunnels/
# Edit deploy-commercial-vpn.sh to set COMMERCIAL_VPC_ID
./deploy-commercial-vpn.sh
```

### 3. Test Full Connectivity
```bash
AWS_PROFILE=govcloud ./scripts/test-vpn-tunnel-connectivity.sh
```

## 📊 **Key Information**

### GovCloud VPN Details
- **Connection ID**: `vpn-031cfaeb996f62462`
- **Gateway ID**: `vgw-0ff3d67133a602ce9`
- **Tunnel 1 IP**: `15.200.132.106`
- **Tunnel 2 IP**: `56.137.42.243`

### Commercial AWS Requirements
- **Customer Gateway IP**: `15.200.132.106` (use GovCloud VPN Gateway IP)
- **BGP ASN**: `65000`
- **Static Routes**: `10.0.0.0/16` (GovCloud VPC CIDR)

### Pre-shared Keys
- **Tunnel 1**: `E9oMMrDgiQK9abT6tQWOwq4ahMQrDZnF`
- **Tunnel 2**: `Tt6eQxek8cJfOgvtS8QJAe0uFBLgiPy_`

## 🔧 **Manual AWS Console Setup (Commercial AWS)**

1. **Customer Gateway**:
   - Name: `dual-routing-api-gateway-prod-govcloud-cgw`
   - IP: `15.200.132.106`
   - BGP ASN: `65000`

2. **VPN Gateway**:
   - Name: `dual-routing-api-gateway-prod-commercial-vgw`
   - ASN: Amazon default
   - Attach to your Commercial VPC

3. **VPN Connection**:
   - Name: `dual-routing-api-gateway-prod-govcloud-vpn`
   - Customer Gateway: Select created gateway
   - VPN Gateway: Select created gateway
   - Routing: Static
   - Static Routes: `10.0.0.0/16`

4. **Route Tables**:
   - Add route: `10.0.0.0/16` → VPN Gateway
   - Enable route propagation

## ✅ **Success Indicators**

- VPN tunnel status: `UP` (at least one)
- Lambda response: HTTP 200 for VPN requests
- Network test: Successful connection to Commercial AWS
- Bedrock API: Successful API calls through VPN

## 🚨 **Troubleshooting**

| Status | Issue | Action |
|--------|-------|--------|
| Tunnels DOWN | Commercial AWS not configured | Deploy Commercial infrastructure |
| 502/503 Errors | Network connectivity | Check routing and security groups |
| 401/403 Errors | Authentication | Update bearer token |
| Timeouts | Connectivity | Check VPN tunnel status |

## 📞 **Quick Commands**

```bash
# Check tunnel status
aws --profile govcloud ec2 describe-vpn-connections --vpn-connection-ids vpn-031cfaeb996f62462

# Test Lambda function
aws --profile govcloud lambda invoke --function-name dual-routing-api-gateway-prod-vpn-lambda --payload '{"httpMethod":"GET","path":"/vpn/health"}' response.json

# View Lambda logs
aws --profile govcloud logs tail /aws/lambda/dual-routing-api-gateway-prod-vpn-lambda --follow

# Full connectivity test
./scripts/test-vpn-tunnel-connectivity.sh
```

## 📁 **Generated Files**

- `commercial-customer-gateway.yaml` - CloudFormation template
- `deploy-commercial-vpn.sh` - Deployment script
- `tunnel-configuration-summary.md` - Detailed configuration
- `../docs/vpn-tunnel-setup-guide.md` - Complete setup guide