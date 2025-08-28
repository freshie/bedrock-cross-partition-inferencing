#!/bin/bash
# VPN Connectivity Configuration Example
# This is an example of what config-vpn.sh looks like after extraction
# Generated automatically by VPNConfigManager
# Project: cross-partition-inference
# Environment: dev
# Generated: 2024-01-15T10:30:00.000Z

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Loading VPN Connectivity Configuration${NC}"
echo -e "${BLUE}Project: cross-partition-inference${NC}"
echo -e "${BLUE}Environment: dev${NC}"
echo ""

# Project Configuration
export PROJECT_NAME="cross-partition-inference"
export ENVIRONMENT="dev"
export ROUTING_METHOD="vpn"

# VPC Configuration
export GOVCLOUD_VPC_ID="vpc-0123456789abcdef0"
export GOVCLOUD_VPC_CIDR="10.0.0.0/16"
export GOVCLOUD_PRIVATE_SUBNET_ID="subnet-0123456789abcdef0"
export GOVCLOUD_VPN_SUBNET_ID="subnet-0123456789abcdef1"
export GOVCLOUD_LAMBDA_SG_ID="sg-0123456789abcdef0"
export COMMERCIAL_VPC_ID="vpc-0987654321fedcba0"
export COMMERCIAL_VPC_CIDR="172.16.0.0/16"
export COMMERCIAL_PRIVATE_SUBNET_ID="subnet-0987654321fedcba0"
export COMMERCIAL_VPN_SUBNET_ID="subnet-0987654321fedcba1"

# VPC Endpoint Configuration
export VPC_ENDPOINT_SECRETS="vpce-0123456789abcdef0-12345678.secretsmanager.us-gov-west-1.vpce.amazonaws.com"
export VPC_ENDPOINT_DYNAMODB="vpce-0123456789abcdef1-12345678.dynamodb.us-gov-west-1.vpce.amazonaws.com"
export VPC_ENDPOINT_LOGS="vpce-0123456789abcdef2-12345678.logs.us-gov-west-1.vpce.amazonaws.com"
export VPC_ENDPOINT_MONITORING="vpce-0123456789abcdef3-12345678.monitoring.us-gov-west-1.vpce.amazonaws.com"
export COMMERCIAL_BEDROCK_ENDPOINT="vpce-0987654321fedcba0-87654321.bedrock-runtime.us-east-1.vpce.amazonaws.com"
export COMMERCIAL_LOGS_ENDPOINT="vpce-0987654321fedcba1-87654321.logs.us-east-1.vpce.amazonaws.com"
export COMMERCIAL_MONITORING_ENDPOINT="vpce-0987654321fedcba2-87654321.monitoring.us-east-1.vpce.amazonaws.com"

# VPN Configuration
export GOVCLOUD_VPN_CONNECTION_ID="vpn-0123456789abcdef0"
export GOVCLOUD_VPN_STATE="available"
export GOVCLOUD_VPN_TUNNEL_1_IP="203.0.113.10"
export GOVCLOUD_VPN_TUNNEL_1_STATUS="UP"
export GOVCLOUD_VPN_TUNNEL_2_IP="203.0.113.11"
export GOVCLOUD_VPN_TUNNEL_2_STATUS="UP"
export COMMERCIAL_VPN_CONNECTION_ID="vpn-0987654321fedcba0"
export COMMERCIAL_VPN_STATE="available"
export COMMERCIAL_VPN_TUNNEL_1_IP="198.51.100.10"
export COMMERCIAL_VPN_TUNNEL_1_STATUS="UP"
export COMMERCIAL_VPN_TUNNEL_2_IP="198.51.100.11"
export COMMERCIAL_VPN_TUNNEL_2_STATUS="DOWN"

# Lambda Configuration
export LAMBDA_FUNCTION_NAME="cross-partition-inference-cross-partition-inference-dev"
export LAMBDA_FUNCTION_ARN="arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:cross-partition-inference-cross-partition-inference-dev"
export LAMBDA_ROLE_ARN="arn:aws-us-gov:iam::123456789012:role/cross-partition-inference-lambda-role-dev"
export COMMERCIAL_CREDENTIALS_SECRET="cross-partition-inference-commercial-credentials-dev"
export REQUEST_LOG_TABLE="cross-partition-inference-request-log-dev"

# Monitoring Configuration
export CLOUDWATCH_LOG_GROUP="/aws/lambda/cross-partition-inference-cross-partition-inference"
export CLOUDWATCH_NAMESPACE="cross-partition-inference/VPN"
export MONITORING_DASHBOARD_URL="https://us-gov-west-1.console.amazonaws-us-gov.com/cloudwatch/home?region=us-gov-west-1#dashboards:name=cross-partition-inference-vpn-monitoring"
export ALARM_TOPIC_ARN="arn:aws-us-gov:sns:us-gov-west-1:123456789012:cross-partition-inference-vpn-alarms-dev"

# Configuration Validation Functions

validate_vpn_config() {
    echo -e "${YELLOW}🔍 Validating VPN Configuration...${NC}"
    
    local errors=0
    
    # Check required variables
    required_vars=(
        "PROJECT_NAME"
        "ENVIRONMENT"
        "GOVCLOUD_VPC_ID"
        "COMMERCIAL_VPC_ID"
        "VPC_ENDPOINT_SECRETS"
        "COMMERCIAL_BEDROCK_ENDPOINT"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo -e "${RED}❌ Missing required variable: $var${NC}"
            ((errors++))
        else
            echo -e "${GREEN}✅ $var is set${NC}"
        fi
    done
    
    # Check VPN tunnel status
    if [ -n "$GOVCLOUD_VPN_TUNNEL_1_STATUS" ]; then
        if [ "$GOVCLOUD_VPN_TUNNEL_1_STATUS" = "UP" ]; then
            echo -e "${GREEN}✅ GovCloud VPN Tunnel 1 is UP${NC}"
        else
            echo -e "${YELLOW}⚠️ GovCloud VPN Tunnel 1 status: $GOVCLOUD_VPN_TUNNEL_1_STATUS${NC}"
        fi
    fi
    
    if [ -n "$COMMERCIAL_VPN_TUNNEL_1_STATUS" ]; then
        if [ "$COMMERCIAL_VPN_TUNNEL_1_STATUS" = "UP" ]; then
            echo -e "${GREEN}✅ Commercial VPN Tunnel 1 is UP${NC}"
        else
            echo -e "${YELLOW}⚠️ Commercial VPN Tunnel 1 status: $COMMERCIAL_VPN_TUNNEL_1_STATUS${NC}"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}🎉 VPN configuration validation passed!${NC}"
        return 0
    else
        echo -e "${RED}❌ VPN configuration validation failed with $errors error(s)${NC}"
        return 1
    fi
}

test_vpn_connectivity() {
    echo -e "${YELLOW}🔗 Testing VPN Connectivity...${NC}"
    
    # Test VPC endpoint connectivity
    if [ -n "$VPC_ENDPOINT_SECRETS" ]; then
        echo -e "${BLUE}Testing Secrets Manager VPC endpoint...${NC}"
        if timeout 10 nc -z $(echo $VPC_ENDPOINT_SECRETS | cut -d'.' -f1) 443 2>/dev/null; then
            echo -e "${GREEN}✅ Secrets Manager VPC endpoint is reachable${NC}"
        else
            echo -e "${RED}❌ Secrets Manager VPC endpoint is not reachable${NC}"
        fi
    fi
    
    # Test cross-partition connectivity (if VPN is up)
    if [ "$GOVCLOUD_VPN_TUNNEL_1_STATUS" = "UP" ] && [ "$COMMERCIAL_VPN_TUNNEL_1_STATUS" = "UP" ]; then
        echo -e "${GREEN}✅ VPN tunnels are up - cross-partition connectivity should be available${NC}"
    else
        echo -e "${YELLOW}⚠️ VPN tunnels are not fully up - cross-partition connectivity may be limited${NC}"
    fi
}

show_vpn_status() {
    echo -e "${BLUE}📊 VPN Status Summary${NC}"
    echo "=================================="
    echo "Project: $PROJECT_NAME"
    echo "Environment: $ENVIRONMENT"
    echo "Routing Method: $ROUTING_METHOD"
    echo ""
    
    echo -e "${BLUE}GovCloud VPC:${NC}"
    echo "  VPC ID: $GOVCLOUD_VPC_ID"
    echo "  CIDR: $GOVCLOUD_VPC_CIDR"
    echo "  VPN Connection: $GOVCLOUD_VPN_CONNECTION_ID"
    echo "  VPN State: $GOVCLOUD_VPN_STATE"
    echo "  Tunnel 1 Status: $GOVCLOUD_VPN_TUNNEL_1_STATUS"
    echo "  Tunnel 2 Status: $GOVCLOUD_VPN_TUNNEL_2_STATUS"
    echo ""
    
    echo -e "${BLUE}Commercial VPC:${NC}"
    echo "  VPC ID: $COMMERCIAL_VPC_ID"
    echo "  CIDR: $COMMERCIAL_VPC_CIDR"
    echo "  VPN Connection: $COMMERCIAL_VPN_CONNECTION_ID"
    echo "  VPN State: $COMMERCIAL_VPN_STATE"
    echo "  Tunnel 1 Status: $COMMERCIAL_VPN_TUNNEL_1_STATUS"
    echo "  Tunnel 2 Status: $COMMERCIAL_VPN_TUNNEL_2_STATUS"
    echo ""
    
    echo -e "${BLUE}VPC Endpoints:${NC}"
    echo "  Secrets Manager: $VPC_ENDPOINT_SECRETS"
    echo "  DynamoDB: $VPC_ENDPOINT_DYNAMODB"
    echo "  CloudWatch Logs: $VPC_ENDPOINT_LOGS"
    echo "  Commercial Bedrock: $COMMERCIAL_BEDROCK_ENDPOINT"
    echo ""
    
    echo -e "${BLUE}VPN Routing Configuration:${NC}"
    echo "  GovCloud → Commercial: Via VPN tunnels ($GOVCLOUD_VPN_TUNNEL_1_IP, $GOVCLOUD_VPN_TUNNEL_2_IP)"
    echo "  Commercial → GovCloud: Via VPN tunnels ($COMMERCIAL_VPN_TUNNEL_1_IP, $COMMERCIAL_VPN_TUNNEL_2_IP)"
    echo "  Lambda VPC: $GOVCLOUD_VPC_ID (Private subnet: $GOVCLOUD_PRIVATE_SUBNET_ID)"
    echo "  Cross-partition calls: Lambda → VPN → Commercial Bedrock VPC endpoint"
    echo ""
    
    echo -e "${BLUE}Network Flow:${NC}"
    echo "  1. Lambda function in GovCloud private subnet"
    echo "  2. Uses VPC endpoints for AWS services (Secrets, DynamoDB, CloudWatch)"
    echo "  3. Routes to Commercial partition via VPN tunnels"
    echo "  4. Reaches Bedrock via Commercial VPC endpoint"
    echo "  5. Returns response via same VPN path"
    echo ""
}

# Show VPN routing details
show_vpn_routing() {
    echo -e "${BLUE}🛣️ VPN Routing Configuration${NC}"
    echo "=================================="
    echo ""
    
    echo -e "${BLUE}Network Architecture:${NC}"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
    echo "│                                GovCloud Partition                               │"
    echo "│  ┌─────────────────────────────────────────────────────────────────────────┐    │"
    echo "│  │                        VPC ($GOVCLOUD_VPC_CIDR)                        │    │"
    echo "│  │                                                                         │    │"
    echo "│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │    │"
    echo "│  │  │  Lambda Subnet  │    │  VPC Endpoints  │    │   VPN Subnet    │     │    │"
    echo "│  │  │   (Private)     │    │    Subnet       │    │                 │     │    │"
    echo "│  │  │                 │    │                 │    │  ┌───────────┐  │     │    │"
    echo "│  │  │  ┌───────────┐  │    │  ┌───────────┐  │    │  │    VPN    │  │     │    │"
    echo "│  │  │  │  Lambda   │  │    │  │ Secrets   │  │    │  │  Gateway  │  │     │    │"
    echo "│  │  │  │ Function  │  │    │  │ DynamoDB  │  │    │  │           │  │     │    │"
    echo "│  │  │  │           │  │    │  │CloudWatch │  │    │  └───────────┘  │     │    │"
    echo "│  │  │  └───────────┘  │    │  └───────────┘  │    │                 │     │    │"
    echo "│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘     │    │"
    echo "│  └─────────────────────────────────────────────────────────────────────────┘    │"
    echo "└─────────────────────────────────────────────────────────────────────────────────┘"
    echo "                                       │"
    echo "                                   VPN Tunnel"
    echo "                              ($GOVCLOUD_VPN_TUNNEL_1_IP)"
    echo "                                       │"
    echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
    echo "│                              Commercial Partition                               │"
    echo "│  ┌─────────────────────────────────────────────────────────────────────────┐    │"
    echo "│  │                      VPC ($COMMERCIAL_VPC_CIDR)                       │    │"
    echo "│  │                                                                         │    │"
    echo "│  │  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │    │"
    echo "│  │  │   VPN Subnet    │    │  VPC Endpoints  │    │  Private Subnet │     │    │"
    echo "│  │  │                 │    │    Subnet       │    │   (Reserved)    │     │    │"
    echo "│  │  │  ┌───────────┐  │    │                 │    │                 │     │    │"
    echo "│  │  │  │    VPN    │  │    │  ┌───────────┐  │    │                 │     │    │"
    echo "│  │  │  │  Gateway  │  │    │  │  Bedrock  │  │    │                 │     │    │"
    echo "│  │  │  │           │  │    │  │CloudWatch │  │    │                 │     │    │"
    echo "│  │  │  └───────────┘  │    │  └───────────┘  │    │                 │     │    │"
    echo "│  │  └─────────────────┘    └─────────────────┘    └─────────────────┘     │    │"
    echo "│  └─────────────────────────────────────────────────────────────────────────┘    │"
    echo "└─────────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    
    echo -e "${BLUE}Traffic Flow:${NC}"
    echo "1. Lambda function starts in GovCloud private subnet"
    echo "2. Accesses local AWS services via VPC endpoints (no internet)"
    echo "3. For Bedrock requests, routes through VPN tunnel to Commercial"
    echo "4. Commercial VPC receives traffic via VPN gateway"
    echo "5. Traffic reaches Bedrock via Commercial VPC endpoint"
    echo "6. Response returns via same VPN path"
    echo ""
    
    echo -e "${BLUE}Security Features:${NC}"
    echo "• No internet gateways in either VPC (complete isolation)"
    echo "• All AWS service access via VPC endpoints"
    echo "• IPSec encryption for cross-partition traffic"
    echo "• Security groups restrict traffic to necessary ports"
    echo "• Network ACLs provide additional filtering"
    echo "• VPC Flow Logs capture all network traffic"
    echo ""
    
    echo -e "${BLUE}Redundancy:${NC}"
    echo "• Dual VPN tunnels for high availability"
    echo "• BGP routing for automatic failover"
    echo "• Multiple Availability Zones where supported"
    echo ""
}

# Auto-run validation if script is sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script is being executed directly
    validate_vpn_config
    test_vpn_connectivity
    show_vpn_status
else
    # Script is being sourced
    echo -e "${GREEN}✅ VPN configuration loaded successfully${NC}"
    echo -e "${BLUE}Available functions: validate_vpn_config, test_vpn_connectivity, show_vpn_status, show_vpn_routing${NC}"
fi