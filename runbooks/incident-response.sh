#!/bin/bash

# VPN Incident Response Runbook
# This script provides automated incident response procedures

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

# Incident types
INCIDENT_TYPES=(
    "vpn-outage:Complete VPN outage"
    "tunnel-down:Single VPN tunnel down"
    "lambda-errors:High Lambda error rate"
    "performance:Performance degradation"
    "security:Security incident"
)

show_usage() {
    echo "Usage: $0 <incident-type> [options]"
    echo ""
    echo "Incident Types:"
    for incident in "${INCIDENT_TYPES[@]}"; do
        IFS=':' read -r type desc <<< "$incident"
        echo "  $type: $desc"
    done
    echo ""
    echo "Options:"
    echo "  --severity LEVEL    Incident severity (1-4, default: 2)"
    echo "  --auto-resolve      Attempt automatic resolution"
    echo "  --report-only       Generate report only, no actions"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 vpn-outage --severity 1"
    echo "  $0 tunnel-down --auto-resolve"
    echo "  $0 lambda-errors --report-only"
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

INCIDENT_TYPE="$1"
shift

SEVERITY=2
AUTO_RESOLVE=false
REPORT_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --auto-resolve)
            AUTO_RESOLVE=true
            shift
            ;;
        --report-only)
            REPORT_ONLY=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# Load configuration
if [ -f "config-vpn.sh" ]; then
    source config-vpn.sh
else
    echo -e "${RED}❌ config-vpn.sh not found. Please run extract-vpn-config.sh first.${NC}"
    exit 1
fi

# Create incident report directory
INCIDENT_ID="INC-$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="./incident-reports/$INCIDENT_ID"
mkdir -p "$REPORT_DIR"

echo -e "${BLUE}🚨 VPN Incident Response${NC}"
echo -e "${BLUE}Incident ID: $INCIDENT_ID${NC}"
echo -e "${BLUE}Type: $INCIDENT_TYPE${NC}"
echo -e "${BLUE}Severity: $SEVERITY${NC}"
echo -e "${BLUE}Report Directory: $REPORT_DIR${NC}"
echo ""

# Function to collect diagnostic information
collect_diagnostics() {
    echo -e "${YELLOW}📊 Collecting diagnostic information...${NC}"
    
    # System status
    ./scripts/get-vpn-status.sh > "$REPORT_DIR/vpn-status.txt"
    ./scripts/validate-vpn-connectivity.sh --verbose > "$REPORT_DIR/connectivity-validation.txt" 2>&1
    
    # CloudWatch logs
    aws logs filter-log-events \
        --log-group-name "$CLOUDWATCH_LOG_GROUP" \
        --start-time $(date -d '2 hours ago' +%s)000 \
        --filter-pattern "ERROR" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 > "$REPORT_DIR/lambda-errors.json"
    
    # VPN connection details
    aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$GOVCLOUD_VPN_CONNECTION_ID" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 > "$REPORT_DIR/govcloud-vpn-details.json"
    
    aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$COMMERCIAL_VPN_CONNECTION_ID" \
        --profile "$COMMERCIAL_PROFILE" \
        --region us-east-1 > "$REPORT_DIR/commercial-vpn-details.json"
    
    # CloudWatch alarms
    aws cloudwatch describe-alarms \
        --state-value ALARM \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 > "$REPORT_DIR/active-alarms.json"
    
    echo -e "${GREEN}✅ Diagnostic information collected${NC}"
}

# Function to handle VPN outage
handle_vpn_outage() {
    echo -e "${RED}🚨 Handling complete VPN outage${NC}"
    
    # Check AWS service health
    echo -e "${YELLOW}🔍 Checking AWS service health...${NC}"
    curl -s "https://status.aws.amazon.com/" | grep -i "service is operating normally" || echo "AWS service issues detected"
    
    # Check VPN connection status
    echo -e "${YELLOW}🔍 Checking VPN connection status...${NC}"
    GOVCLOUD_VPN_STATE=$(aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$GOVCLOUD_VPN_CONNECTION_ID" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query 'VpnConnections[0].State' \
        --output text)
    
    COMMERCIAL_VPN_STATE=$(aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$COMMERCIAL_VPN_CONNECTION_ID" \
        --profile "$COMMERCIAL_PROFILE" \
        --region us-east-1 \
        --query 'VpnConnections[0].State' \
        --output text)
    
    echo "GovCloud VPN State: $GOVCLOUD_VPN_STATE"
    echo "Commercial VPN State: $COMMERCIAL_VPN_STATE"
    
    if [ "$AUTO_RESOLVE" = true ]; then
        echo -e "${YELLOW}🔧 Attempting automatic resolution...${NC}"
        
        # Reset VPN connections if they're in failed state
        if [ "$GOVCLOUD_VPN_STATE" != "available" ]; then
            echo "Resetting GovCloud VPN connection..."
            aws ec2 reset-vpn-connection \
                --vpn-connection-id "$GOVCLOUD_VPN_CONNECTION_ID" \
                --profile "$GOVCLOUD_PROFILE" \
                --region us-gov-west-1
        fi
        
        if [ "$COMMERCIAL_VPN_STATE" != "available" ]; then
            echo "Resetting Commercial VPN connection..."
            aws ec2 reset-vpn-connection \
                --vpn-connection-id "$COMMERCIAL_VPN_CONNECTION_ID" \
                --profile "$COMMERCIAL_PROFILE" \
                --region us-east-1
        fi
        
        echo -e "${YELLOW}⏳ Waiting for VPN recovery (5 minutes)...${NC}"
        sleep 300
        
        # Check if recovery was successful
        ./scripts/get-vpn-status.sh summary
    fi
    
    # Generate incident report
    cat > "$REPORT_DIR/incident-summary.txt" << EOF
Incident Summary
================
Incident ID: $INCIDENT_ID
Type: Complete VPN Outage
Severity: $SEVERITY
Start Time: $(date)

Initial Status:
- GovCloud VPN State: $GOVCLOUD_VPN_STATE
- Commercial VPN State: $COMMERCIAL_VPN_STATE

Actions Taken:
- Collected diagnostic information
- Checked AWS service health
- $([ "$AUTO_RESOLVE" = true ] && echo "Attempted automatic VPN reset" || echo "Manual intervention required")

Next Steps:
1. Monitor VPN tunnel recovery
2. Test cross-partition connectivity
3. Review root cause analysis
4. Update incident documentation
EOF
}

# Function to handle single tunnel down
handle_tunnel_down() {
    echo -e "${YELLOW}⚠️ Handling single VPN tunnel down${NC}"
    
    # Check tunnel status
    GOVCLOUD_TUNNELS=$(aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$GOVCLOUD_VPN_CONNECTION_ID" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query 'VpnConnections[0].VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status}' \
        --output table)
    
    echo "GovCloud Tunnel Status:"
    echo "$GOVCLOUD_TUNNELS"
    
    COMMERCIAL_TUNNELS=$(aws ec2 describe-vpn-connections \
        --vpn-connection-ids "$COMMERCIAL_VPN_CONNECTION_ID" \
        --profile "$COMMERCIAL_PROFILE" \
        --region us-east-1 \
        --query 'VpnConnections[0].VgwTelemetry[*].{IP:OutsideIpAddress,Status:Status}' \
        --output table)
    
    echo "Commercial Tunnel Status:"
    echo "$COMMERCIAL_TUNNELS"
    
    # Check if BGP failover is working
    echo -e "${YELLOW}🔍 Checking BGP failover...${NC}"
    UP_TUNNELS=$(echo "$GOVCLOUD_TUNNELS" | grep -c "UP" || echo "0")
    
    if [ "$UP_TUNNELS" -gt 0 ]; then
        echo -e "${GREEN}✅ At least one tunnel is UP, BGP failover should be working${NC}"
    else
        echo -e "${RED}❌ No tunnels are UP, escalating to VPN outage procedure${NC}"
        handle_vpn_outage
        return
    fi
    
    if [ "$AUTO_RESOLVE" = true ]; then
        echo -e "${YELLOW}🔧 Monitoring for automatic tunnel recovery...${NC}"
        # VPN tunnels often recover automatically, monitor for 10 minutes
        for i in {1..10}; do
            sleep 60
            echo "Checking tunnel status (attempt $i/10)..."
            ./scripts/get-vpn-status.sh summary
            
            # Check if all tunnels are back up
            CURRENT_UP=$(./scripts/get-vpn-status.sh summary | grep -c "UP" || echo "0")
            if [ "$CURRENT_UP" -ge 4 ]; then  # 2 tunnels per connection, 2 connections
                echo -e "${GREEN}✅ All tunnels recovered${NC}"
                break
            fi
        done
    fi
}

# Function to handle Lambda errors
handle_lambda_errors() {
    echo -e "${YELLOW}⚠️ Handling high Lambda error rate${NC}"
    
    # Get recent error statistics
    ERROR_COUNT=$(aws logs filter-log-events \
        --log-group-name "$CLOUDWATCH_LOG_GROUP" \
        --start-time $(date -d '1 hour ago' +%s)000 \
        --filter-pattern "ERROR" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query 'length(events)' \
        --output text)
    
    echo "Error count in last hour: $ERROR_COUNT"
    
    # Check Lambda function configuration
    LAMBDA_CONFIG=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query '{State:State,Timeout:Timeout,Memory:MemorySize,VpcConfig:VpcConfig.VpcId}')
    
    echo "Lambda Configuration:"
    echo "$LAMBDA_CONFIG"
    
    # Check VPC connectivity
    echo -e "${YELLOW}🔍 Testing VPC connectivity...${NC}"
    test_vpn_connectivity
    
    if [ "$AUTO_RESOLVE" = true ] && [ "$ERROR_COUNT" -gt 10 ]; then
        echo -e "${YELLOW}🔧 High error count detected, updating Lambda configuration...${NC}"
        
        # Increase timeout if it's low
        CURRENT_TIMEOUT=$(echo "$LAMBDA_CONFIG" | jq -r '.Timeout')
        if [ "$CURRENT_TIMEOUT" -lt 30 ]; then
            echo "Increasing Lambda timeout to 30 seconds..."
            aws lambda update-function-configuration \
                --function-name "$LAMBDA_FUNCTION_NAME" \
                --timeout 30 \
                --profile "$GOVCLOUD_PROFILE" \
                --region us-gov-west-1
        fi
        
        # Increase memory if it's low
        CURRENT_MEMORY=$(echo "$LAMBDA_CONFIG" | jq -r '.MemorySize')
        if [ "$CURRENT_MEMORY" -lt 512 ]; then
            echo "Increasing Lambda memory to 512 MB..."
            aws lambda update-function-configuration \
                --function-name "$LAMBDA_FUNCTION_NAME" \
                --memory-size 512 \
                --profile "$GOVCLOUD_PROFILE" \
                --region us-gov-west-1
        fi
    fi
}

# Function to handle performance issues
handle_performance() {
    echo -e "${YELLOW}⚠️ Handling performance degradation${NC}"
    
    # Get performance metrics
    aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Duration \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 300 \
        --statistics Average,Maximum \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 > "$REPORT_DIR/lambda-performance.json"
    
    # Check VPN latency
    aws cloudwatch get-metric-statistics \
        --namespace AWS/VPN \
        --metric-name TunnelLatency \
        --dimensions Name=VpnId,Value="$GOVCLOUD_VPN_CONNECTION_ID" \
        --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 300 \
        --statistics Average,Maximum \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 > "$REPORT_DIR/vpn-latency.json"
    
    echo -e "${GREEN}✅ Performance metrics collected${NC}"
}

# Function to handle security incidents
handle_security() {
    echo -e "${RED}🔒 Handling security incident${NC}"
    
    # Check VPC Flow Logs for suspicious activity
    aws logs filter-log-events \
        --log-group-name "/aws/vpc/flowlogs" \
        --start-time $(date -d '2 hours ago' +%s)000 \
        --filter-pattern "{ $.action = \"REJECT\" }" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 > "$REPORT_DIR/rejected-traffic.json"
    
    # Check CloudTrail for unauthorized API calls
    aws logs filter-log-events \
        --log-group-name "CloudTrail/APILogs" \
        --start-time $(date -d '2 hours ago' +%s)000 \
        --filter-pattern "{ $.errorCode exists }" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 > "$REPORT_DIR/api-errors.json"
    
    echo -e "${RED}⚠️ Security incident requires manual investigation${NC}"
    echo -e "${RED}Review collected logs and contact security team${NC}"
}

# Main incident handling logic
main() {
    # Collect diagnostics for all incident types
    collect_diagnostics
    
    if [ "$REPORT_ONLY" = true ]; then
        echo -e "${BLUE}📊 Report-only mode, skipping resolution actions${NC}"
        echo -e "${BLUE}Diagnostic information saved to: $REPORT_DIR${NC}"
        exit 0
    fi
    
    # Handle specific incident types
    case "$INCIDENT_TYPE" in
        "vpn-outage")
            handle_vpn_outage
            ;;
        "tunnel-down")
            handle_tunnel_down
            ;;
        "lambda-errors")
            handle_lambda_errors
            ;;
        "performance")
            handle_performance
            ;;
        "security")
            handle_security
            ;;
        *)
            echo -e "${RED}❌ Unknown incident type: $INCIDENT_TYPE${NC}"
            show_usage
            exit 1
            ;;
    esac
    
    # Final status check
    echo -e "${BLUE}📊 Final system status:${NC}"
    ./scripts/get-vpn-status.sh summary
    
    echo ""
    echo -e "${GREEN}🎉 Incident response completed${NC}"
    echo -e "${BLUE}📁 Incident report saved to: $REPORT_DIR${NC}"
    echo -e "${BLUE}📋 Next steps:${NC}"
    echo -e "${BLUE}  1. Review incident report${NC}"
    echo -e "${BLUE}  2. Update incident tracking system${NC}"
    echo -e "${BLUE}  3. Conduct post-incident review${NC}"
    echo -e "${BLUE}  4. Update runbooks if needed${NC}"
}

# Run main function
main "$@"