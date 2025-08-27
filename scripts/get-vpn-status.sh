#!/bin/bash

# Get Real-time VPN Tunnel Status
# This script retrieves current VPN tunnel status from AWS APIs

set -e

# Configuration
PROJECT_NAME="cross-partition-inference"
ENVIRONMENT="dev"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Getting Real-time VPN Tunnel Status${NC}"
echo -e "${BLUE}Project: ${PROJECT_NAME}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo ""

# Function to get VPN status for a partition
get_partition_vpn_status() {
    local profile=$1
    local partition=$2
    local region=$3
    
    echo -e "${YELLOW}📡 Getting ${partition} VPN status...${NC}"
    
    # Get VPN connections
    local vpn_connections
    vpn_connections=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "${profile}" \
        --region "${region}" \
        --query 'VpnConnections[*].{
            VpnConnectionId:VpnConnectionId,
            State:State,
            Type:Type,
            CustomerGatewayId:CustomerGatewayId,
            VpnGatewayId:VpnGatewayId,
            Tunnels:VgwTelemetry[*].{
                OutsideIpAddress:OutsideIpAddress,
                Status:Status,
                LastStatusChange:LastStatusChange,
                StatusMessage:StatusMessage,
                AcceptedRouteCount:AcceptedRouteCount
            }
        }' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$vpn_connections" = "[]" ]; then
        echo -e "${YELLOW}⚠️ No VPN connections found in ${partition}${NC}"
        return
    fi
    
    # Parse and display VPN connection status
    echo "$vpn_connections" | jq -r '.[] | 
        "VPN Connection: " + .VpnConnectionId + 
        "\n  State: " + .State + 
        "\n  Type: " + .Type + 
        "\n  Customer Gateway: " + (.CustomerGatewayId // "N/A") + 
        "\n  VPN Gateway: " + (.VpnGatewayId // "N/A") + 
        "\n  Tunnels:"'
    
    # Display tunnel details with color coding
    echo "$vpn_connections" | jq -r '.[] | .Tunnels[] | 
        "    IP: " + .OutsideIpAddress + 
        " | Status: " + .Status + 
        " | Routes: " + (.AcceptedRouteCount | tostring) + 
        " | Last Change: " + (.LastStatusChange // "N/A")' | \
    while IFS= read -r line; do
        if [[ $line == *"Status: UP"* ]]; then
            echo -e "${GREEN}  ✅ $line${NC}"
        elif [[ $line == *"Status: DOWN"* ]]; then
            echo -e "${RED}  ❌ $line${NC}"
        else
            echo -e "${YELLOW}  ⚠️ $line${NC}"
        fi
    done
    
    echo ""
}

# Function to get VPN Gateway status
get_vpn_gateway_status() {
    local profile=$1
    local partition=$2
    local region=$3
    
    echo -e "${YELLOW}🏗️ Getting ${partition} VPN Gateway status...${NC}"
    
    local vpn_gateways
    vpn_gateways=$(aws ec2 describe-vpn-gateways \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "${profile}" \
        --region "${region}" \
        --query 'VpnGateways[*].{
            VpnGatewayId:VpnGatewayId,
            State:State,
            Type:Type,
            AvailabilityZone:AvailabilityZone,
            VpcAttachments:VpcAttachments[*].{
                VpcId:VpcId,
                State:State
            }
        }' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$vpn_gateways" = "[]" ]; then
        echo -e "${YELLOW}⚠️ No VPN gateways found in ${partition}${NC}"
        return
    fi
    
    echo "$vpn_gateways" | jq -r '.[] | 
        "VPN Gateway: " + .VpnGatewayId + 
        "\n  State: " + .State + 
        "\n  Type: " + .Type + 
        "\n  AZ: " + (.AvailabilityZone // "N/A") + 
        "\n  VPC Attachments:"'
    
    echo "$vpn_gateways" | jq -r '.[] | .VpcAttachments[]? | 
        "    VPC: " + .VpcId + " | State: " + .State' | \
    while IFS= read -r line; do
        if [[ $line == *"State: attached"* ]]; then
            echo -e "${GREEN}  ✅ $line${NC}"
        else
            echo -e "${YELLOW}  ⚠️ $line${NC}"
        fi
    done
    
    echo ""
}

# Function to get Customer Gateway status
get_customer_gateway_status() {
    local profile=$1
    local partition=$2
    local region=$3
    
    echo -e "${YELLOW}🏢 Getting ${partition} Customer Gateway status...${NC}"
    
    local customer_gateways
    customer_gateways=$(aws ec2 describe-customer-gateways \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "${profile}" \
        --region "${region}" \
        --query 'CustomerGateways[*].{
            CustomerGatewayId:CustomerGatewayId,
            State:State,
            Type:Type,
            IpAddress:IpAddress,
            BgpAsn:BgpAsn
        }' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$customer_gateways" = "[]" ]; then
        echo -e "${YELLOW}⚠️ No customer gateways found in ${partition}${NC}"
        return
    fi
    
    echo "$customer_gateways" | jq -r '.[] | 
        "Customer Gateway: " + .CustomerGatewayId + 
        "\n  State: " + .State + 
        "\n  Type: " + .Type + 
        "\n  IP Address: " + .IpAddress + 
        "\n  BGP ASN: " + (.BgpAsn | tostring)'
    
    echo ""
}

# Function to test VPN connectivity
test_vpn_connectivity() {
    echo -e "${YELLOW}🔗 Testing VPN Connectivity...${NC}"
    
    # Check if we have a config file to source
    if [ -f "config-vpn.sh" ]; then
        echo -e "${BLUE}Loading configuration from config-vpn.sh...${NC}"
        source config-vpn.sh
        
        # Test VPC endpoint connectivity
        if [ -n "$VPC_ENDPOINT_SECRETS" ]; then
            echo -e "${BLUE}Testing Secrets Manager VPC endpoint...${NC}"
            if timeout 5 nc -z $(echo $VPC_ENDPOINT_SECRETS | cut -d'.' -f1) 443 2>/dev/null; then
                echo -e "${GREEN}✅ Secrets Manager VPC endpoint is reachable${NC}"
            else
                echo -e "${RED}❌ Secrets Manager VPC endpoint is not reachable${NC}"
            fi
        fi
        
        # Check tunnel status from config
        if [ "$GOVCLOUD_VPN_TUNNEL_1_STATUS" = "UP" ] && [ "$COMMERCIAL_VPN_TUNNEL_1_STATUS" = "UP" ]; then
            echo -e "${GREEN}✅ Both primary VPN tunnels are UP${NC}"
        elif [ "$GOVCLOUD_VPN_TUNNEL_1_STATUS" = "UP" ] || [ "$COMMERCIAL_VPN_TUNNEL_1_STATUS" = "UP" ]; then
            echo -e "${YELLOW}⚠️ Only one primary VPN tunnel is UP${NC}"
        else
            echo -e "${RED}❌ Primary VPN tunnels are DOWN${NC}"
        fi
        
        # Check secondary tunnels
        if [ "$GOVCLOUD_VPN_TUNNEL_2_STATUS" = "UP" ] && [ "$COMMERCIAL_VPN_TUNNEL_2_STATUS" = "UP" ]; then
            echo -e "${GREEN}✅ Both secondary VPN tunnels are UP (redundancy available)${NC}"
        fi
        
    else
        echo -e "${YELLOW}⚠️ config-vpn.sh not found. Run extract-vpn-config.sh first.${NC}"
    fi
    
    echo ""
}

# Function to generate status summary
generate_status_summary() {
    echo -e "${BLUE}📊 VPN Status Summary${NC}"
    echo "=================================="
    
    # Count active tunnels
    local govcloud_active_tunnels=0
    local commercial_active_tunnels=0
    
    # GovCloud tunnels
    local govcloud_vpn_status
    govcloud_vpn_status=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "${GOVCLOUD_PROFILE}" \
        --region "us-gov-west-1" \
        --query 'VpnConnections[*].VgwTelemetry[?Status==`UP`]' \
        --output json 2>/dev/null || echo "[]")
    
    govcloud_active_tunnels=$(echo "$govcloud_vpn_status" | jq '[.[][]] | length')
    
    # Commercial tunnels
    local commercial_vpn_status
    commercial_vpn_status=$(aws ec2 describe-vpn-connections \
        --filters "Name=tag:Project,Values=${PROJECT_NAME}" \
        --profile "${COMMERCIAL_PROFILE}" \
        --region "us-east-1" \
        --query 'VpnConnections[*].VgwTelemetry[?Status==`UP`]' \
        --output json 2>/dev/null || echo "[]")
    
    commercial_active_tunnels=$(echo "$commercial_vpn_status" | jq '[.[][]] | length')
    
    echo "GovCloud Active Tunnels: $govcloud_active_tunnels"
    echo "Commercial Active Tunnels: $commercial_active_tunnels"
    
    # Overall status
    if [ "$govcloud_active_tunnels" -gt 0 ] && [ "$commercial_active_tunnels" -gt 0 ]; then
        echo -e "${GREEN}Overall Status: ✅ OPERATIONAL${NC}"
        echo "Cross-partition connectivity is available"
    elif [ "$govcloud_active_tunnels" -gt 0 ] || [ "$commercial_active_tunnels" -gt 0 ]; then
        echo -e "${YELLOW}Overall Status: ⚠️ PARTIAL${NC}"
        echo "Limited connectivity - some tunnels are down"
    else
        echo -e "${RED}Overall Status: ❌ DOWN${NC}"
        echo "No active VPN tunnels found"
    fi
    
    echo ""
    echo "Last checked: $(date)"
    echo ""
}

# Function to watch VPN status (continuous monitoring)
watch_vpn_status() {
    echo -e "${BLUE}👀 Watching VPN Status (Press Ctrl+C to stop)${NC}"
    echo ""
    
    while true; do
        clear
        echo -e "${BLUE}🔄 VPN Status Monitor - $(date)${NC}"
        echo "=================================="
        
        generate_status_summary
        
        echo -e "${BLUE}Refreshing in 30 seconds...${NC}"
        sleep 30
    done
}

# Main execution
case "${1:-status}" in
    "status"|"")
        # Default: show full status
        get_partition_vpn_status "$GOVCLOUD_PROFILE" "GovCloud" "us-gov-west-1"
        get_vpn_gateway_status "$GOVCLOUD_PROFILE" "GovCloud" "us-gov-west-1"
        get_customer_gateway_status "$GOVCLOUD_PROFILE" "GovCloud" "us-gov-west-1"
        
        get_partition_vpn_status "$COMMERCIAL_PROFILE" "Commercial" "us-east-1"
        get_vpn_gateway_status "$COMMERCIAL_PROFILE" "Commercial" "us-east-1"
        get_customer_gateway_status "$COMMERCIAL_PROFILE" "Commercial" "us-east-1"
        
        test_vpn_connectivity
        generate_status_summary
        ;;
    
    "summary")
        # Quick summary only
        generate_status_summary
        ;;
    
    "test")
        # Test connectivity only
        test_vpn_connectivity
        ;;
    
    "watch")
        # Continuous monitoring
        watch_vpn_status
        ;;
    
    "govcloud")
        # GovCloud only
        get_partition_vpn_status "$GOVCLOUD_PROFILE" "GovCloud" "us-gov-west-1"
        get_vpn_gateway_status "$GOVCLOUD_PROFILE" "GovCloud" "us-gov-west-1"
        get_customer_gateway_status "$GOVCLOUD_PROFILE" "GovCloud" "us-gov-west-1"
        ;;
    
    "commercial")
        # Commercial only
        get_partition_vpn_status "$COMMERCIAL_PROFILE" "Commercial" "us-east-1"
        get_vpn_gateway_status "$COMMERCIAL_PROFILE" "Commercial" "us-east-1"
        get_customer_gateway_status "$COMMERCIAL_PROFILE" "Commercial" "us-east-1"
        ;;
    
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  status     Show full VPN status (default)"
        echo "  summary    Show quick status summary"
        echo "  test       Test VPN connectivity"
        echo "  watch      Continuous status monitoring"
        echo "  govcloud   Show GovCloud VPN status only"
        echo "  commercial Show Commercial VPN status only"
        echo "  help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                    # Show full status"
        echo "  $0 summary           # Quick summary"
        echo "  $0 watch             # Monitor continuously"
        echo "  $0 test              # Test connectivity"
        ;;
    
    *)
        echo -e "${RED}❌ Unknown command: $1${NC}"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac