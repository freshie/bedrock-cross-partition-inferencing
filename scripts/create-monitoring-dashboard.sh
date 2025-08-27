#!/bin/bash

# Create VPN Monitoring Dashboard
# This script creates a comprehensive CloudWatch dashboard for VPN monitoring

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

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --govcloud-profile)
            GOVCLOUD_PROFILE="$2"
            shift 2
            ;;
        --commercial-profile)
            COMMERCIAL_PROFILE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --project-name NAME        Project name (default: cross-partition-inference)"
            echo "  --environment ENV          Environment (default: dev)"
            echo "  --govcloud-profile PROFILE AWS CLI profile for GovCloud (default: govcloud)"
            echo "  --commercial-profile PROFILE AWS CLI profile for Commercial (default: commercial)"
            echo "  --help, -h                 Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🔧 Creating VPN Monitoring Dashboard${NC}"
echo -e "${BLUE}Project: ${PROJECT_NAME}${NC}"
echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
echo ""

# Load configuration if available
if [ -f "config-vpn.sh" ]; then
    echo -e "${YELLOW}📋 Loading VPN configuration...${NC}"
    source config-vpn.sh
else
    echo -e "${YELLOW}⚠️ config-vpn.sh not found, using defaults${NC}"
    LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-cross-partition-inference-${ENVIRONMENT}"
    CLOUDWATCH_LOG_GROUP="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    REQUEST_LOG_TABLE="${PROJECT_NAME}-request-log-${ENVIRONMENT}"
    GOVCLOUD_VPN_CONNECTION_ID="vpn-placeholder"
    COMMERCIAL_VPN_CONNECTION_ID="vpn-placeholder"
    GOVCLOUD_VPN_TUNNEL_1_IP="203.0.113.1"
    GOVCLOUD_VPN_TUNNEL_2_IP="203.0.113.2"
    COMMERCIAL_VPN_TUNNEL_1_IP="198.51.100.1"
    COMMERCIAL_VPN_TUNNEL_2_IP="198.51.100.2"
    VPC_ENDPOINT_SECRETS="vpce-placeholder"
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create dashboard JSON from template
DASHBOARD_NAME="${PROJECT_NAME}-vpn-monitoring-${ENVIRONMENT}"
TEMP_DASHBOARD="/tmp/${DASHBOARD_NAME}.json"

echo -e "${YELLOW}📊 Generating dashboard configuration...${NC}"

# Replace variables in template
sed -e "s/\${PROJECT_NAME}/${PROJECT_NAME}/g" \
    -e "s/\${ENVIRONMENT}/${ENVIRONMENT}/g" \
    -e "s/\${LAMBDA_FUNCTION_NAME}/${LAMBDA_FUNCTION_NAME}/g" \
    -e "s/\${CLOUDWATCH_LOG_GROUP}/${CLOUDWATCH_LOG_GROUP//\//\\/}/g" \
    -e "s/\${REQUEST_LOG_TABLE}/${REQUEST_LOG_TABLE}/g" \
    -e "s/\${GOVCLOUD_VPN_CONNECTION_ID}/${GOVCLOUD_VPN_CONNECTION_ID}/g" \
    -e "s/\${COMMERCIAL_VPN_CONNECTION_ID}/${COMMERCIAL_VPN_CONNECTION_ID}/g" \
    -e "s/\${GOVCLOUD_VPN_TUNNEL_1_IP}/${GOVCLOUD_VPN_TUNNEL_1_IP}/g" \
    -e "s/\${GOVCLOUD_VPN_TUNNEL_2_IP}/${GOVCLOUD_VPN_TUNNEL_2_IP}/g" \
    -e "s/\${COMMERCIAL_VPN_TUNNEL_1_IP}/${COMMERCIAL_VPN_TUNNEL_1_IP}/g" \
    -e "s/\${COMMERCIAL_VPN_TUNNEL_2_IP}/${COMMERCIAL_VPN_TUNNEL_2_IP}/g" \
    -e "s/\${VPC_ENDPOINT_SECRETS}/${VPC_ENDPOINT_SECRETS}/g" \
    "${SCRIPT_DIR}/../monitoring/vpn-dashboard-template.json" > "$TEMP_DASHBOARD"

# Create dashboard in GovCloud
echo -e "${YELLOW}🏛️ Creating dashboard in GovCloud...${NC}"
aws cloudwatch put-dashboard \
    --dashboard-name "$DASHBOARD_NAME" \
    --dashboard-body file://"$TEMP_DASHBOARD" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ GovCloud dashboard created successfully${NC}"
    GOVCLOUD_DASHBOARD_URL="https://us-gov-west-1.console.amazonaws-us-gov.com/cloudwatch/home?region=us-gov-west-1#dashboards:name=${DASHBOARD_NAME}"
    echo -e "${BLUE}📊 GovCloud Dashboard URL: ${GOVCLOUD_DASHBOARD_URL}${NC}"
else
    echo -e "${RED}❌ Failed to create GovCloud dashboard${NC}"
    exit 1
fi

# Create simplified dashboard for Commercial (VPN metrics only)
echo -e "${YELLOW}🏢 Creating dashboard in Commercial...${NC}"

# Create simplified Commercial dashboard
COMMERCIAL_DASHBOARD_JSON="{
    \"widgets\": [
        {
            \"type\": \"metric\",
            \"x\": 0,
            \"y\": 0,
            \"width\": 12,
            \"height\": 6,
            \"properties\": {
                \"metrics\": [
                    [ \"AWS/VPN\", \"TunnelState\", \"VpnId\", \"${COMMERCIAL_VPN_CONNECTION_ID}\", \"TunnelIpAddress\", \"${COMMERCIAL_VPN_TUNNEL_1_IP}\" ],
                    [ \"...\", \"${COMMERCIAL_VPN_TUNNEL_2_IP}\" ]
                ],
                \"view\": \"timeSeries\",
                \"stacked\": false,
                \"region\": \"us-east-1\",
                \"title\": \"Commercial VPN Tunnel Status\",
                \"period\": 300,
                \"stat\": \"Maximum\"
            }
        },
        {
            \"type\": \"metric\",
            \"x\": 12,
            \"y\": 0,
            \"width\": 12,
            \"height\": 6,
            \"properties\": {
                \"metrics\": [
                    [ \"AWS/VPN\", \"TunnelLatency\", \"VpnId\", \"${COMMERCIAL_VPN_CONNECTION_ID}\", \"TunnelIpAddress\", \"${COMMERCIAL_VPN_TUNNEL_1_IP}\" ],
                    [ \"...\", \"${COMMERCIAL_VPN_TUNNEL_2_IP}\" ]
                ],
                \"view\": \"timeSeries\",
                \"stacked\": false,
                \"region\": \"us-east-1\",
                \"title\": \"Commercial VPN Tunnel Latency\",
                \"period\": 300,
                \"stat\": \"Average\"
            }
        }
    ]
}"

echo "$COMMERCIAL_DASHBOARD_JSON" > "/tmp/${DASHBOARD_NAME}-commercial.json"

aws cloudwatch put-dashboard \
    --dashboard-name "${DASHBOARD_NAME}-commercial" \
    --dashboard-body file://"/tmp/${DASHBOARD_NAME}-commercial.json" \
    --profile "$COMMERCIAL_PROFILE" \
    --region us-east-1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Commercial dashboard created successfully${NC}"
    COMMERCIAL_DASHBOARD_URL="https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=${DASHBOARD_NAME}-commercial"
    echo -e "${BLUE}📊 Commercial Dashboard URL: ${COMMERCIAL_DASHBOARD_URL}${NC}"
else
    echo -e "${RED}❌ Failed to create Commercial dashboard${NC}"
fi

# Create CloudWatch alarms
echo -e "${YELLOW}🚨 Creating CloudWatch alarms...${NC}"

# VPN Tunnel Down Alarm (GovCloud)
aws cloudwatch put-metric-alarm \
    --alarm-name "${PROJECT_NAME}-govcloud-vpn-tunnel-down-${ENVIRONMENT}" \
    --alarm-description "GovCloud VPN tunnel is down" \
    --metric-name TunnelState \
    --namespace AWS/VPN \
    --statistic Maximum \
    --period 300 \
    --threshold 0 \
    --comparison-operator LessThanThreshold \
    --dimensions Name=VpnId,Value="$GOVCLOUD_VPN_CONNECTION_ID" \
    --evaluation-periods 2 \
    --treat-missing-data breaching \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Lambda Error Rate Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${PROJECT_NAME}-lambda-error-rate-${ENVIRONMENT}" \
    --alarm-description "Lambda error rate is high" \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
    --evaluation-periods 3 \
    --treat-missing-data notBreaching \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# Lambda Duration Alarm
aws cloudwatch put-metric-alarm \
    --alarm-name "${PROJECT_NAME}-lambda-duration-${ENVIRONMENT}" \
    --alarm-description "Lambda duration is high" \
    --metric-name Duration \
    --namespace AWS/Lambda \
    --statistic Average \
    --period 300 \
    --threshold 10000 \
    --comparison-operator GreaterThanThreshold \
    --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
    --evaluation-periods 3 \
    --treat-missing-data notBreaching \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1

# VPN Tunnel Down Alarm (Commercial)
aws cloudwatch put-metric-alarm \
    --alarm-name "${PROJECT_NAME}-commercial-vpn-tunnel-down-${ENVIRONMENT}" \
    --alarm-description "Commercial VPN tunnel is down" \
    --metric-name TunnelState \
    --namespace AWS/VPN \
    --statistic Maximum \
    --period 300 \
    --threshold 0 \
    --comparison-operator LessThanThreshold \
    --dimensions Name=VpnId,Value="$COMMERCIAL_VPN_CONNECTION_ID" \
    --evaluation-periods 2 \
    --treat-missing-data breaching \
    --profile "$COMMERCIAL_PROFILE" \
    --region us-east-1

echo -e "${GREEN}✅ CloudWatch alarms created${NC}"

# Clean up temporary files
rm -f "$TEMP_DASHBOARD" "/tmp/${DASHBOARD_NAME}-commercial.json"

echo ""
echo -e "${GREEN}🎉 VPN monitoring dashboard setup completed!${NC}"
echo ""
echo -e "${BLUE}📊 Dashboard URLs:${NC}"
echo -e "${BLUE}  GovCloud: ${GOVCLOUD_DASHBOARD_URL}${NC}"
echo -e "${BLUE}  Commercial: ${COMMERCIAL_DASHBOARD_URL}${NC}"
echo ""
echo -e "${BLUE}📋 Next steps:${NC}"
echo -e "${BLUE}  1. Configure SNS topics for alarm notifications${NC}"
echo -e "${BLUE}  2. Set up email subscriptions for alerts${NC}"
echo -e "${BLUE}  3. Test alarm functionality${NC}"
echo -e "${BLUE}  4. Create operational runbooks${NC}"
echo ""