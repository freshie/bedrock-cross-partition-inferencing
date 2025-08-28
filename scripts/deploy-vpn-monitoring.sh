#!/bin/bash

# Deploy VPN monitoring and alerting infrastructure
# This script deploys comprehensive monitoring for the VPN connectivity solution

set -e

# Configuration
PROJECT_NAME="cross-partition-vpn"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
COMMERCIAL_PROFILE="commercial"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying VPN monitoring and alerting infrastructure${NC}"
echo "Project: $PROJECT_NAME"
echo "Environment: $ENVIRONMENT"
echo ""

# Function to check if AWS CLI profile exists
check_profile() {
    local profile=$1
    if ! aws configure list-profiles | grep -q "^$profile$"; then
        echo -e "${RED}❌ AWS CLI profile '$profile' not found${NC}"
        echo "Please configure the profile using: aws configure --profile $profile"
        exit 1
    fi
}

# Function to get user input for alert configuration
get_alert_configuration() {
    echo -e "${YELLOW}📧 Alert Configuration${NC}"
    
    # Get email for alerts
    read -p "Enter email address for alerts (default: admin@example.com): " ALERT_EMAIL
    ALERT_EMAIL=${ALERT_EMAIL:-admin@example.com}
    
    # Get Slack webhook (optional)
    read -p "Enter Slack webhook URL (optional, press Enter to skip): " SLACK_WEBHOOK
    
    echo ""
    echo -e "${BLUE}Alert Configuration:${NC}"
    echo "Email: $ALERT_EMAIL"
    echo "Slack: ${SLACK_WEBHOOK:-'Not configured'}"
    echo ""
}

# Function to deploy monitoring stack
deploy_monitoring_stack() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    
    echo -e "${YELLOW}📦 Deploying $partition monitoring stack: $stack_name${NC}"
    
    local parameters=(
        "Environment=$ENVIRONMENT"
        "ProjectName=$PROJECT_NAME"
        "AlertEmail=$ALERT_EMAIL"
    )
    
    if [ -n "$SLACK_WEBHOOK" ]; then
        parameters+=("SlackWebhookUrl=$SLACK_WEBHOOK")
    fi
    
    aws cloudformation deploy \
        --profile "$profile" \
        --template-file "../infrastructure/vpn-monitoring-alerting.yaml" \
        --stack-name "$stack_name" \
        --parameter-overrides "${parameters[@]}" \
        --capabilities CAPABILITY_IAM \
        --tags \
            Project="$PROJECT_NAME" \
            Environment="$ENVIRONMENT" \
            Partition="$partition" \
            Component="monitoring-alerting"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $partition monitoring stack deployed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to deploy $partition monitoring stack${NC}"
        exit 1
    fi
}

# Function to get stack outputs
get_stack_outputs() {
    local profile=$1
    local stack_name=$2
    local partition=$3
    
    echo -e "${YELLOW}📋 Getting $partition monitoring stack outputs${NC}"
    
    aws cloudformation describe-stacks \
        --profile "$profile" \
        --stack-name "$stack_name" \
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
        --output table
}

# Function to test alert functionality
test_alerts() {
    local profile=$1
    local partition=$2
    
    echo -e "${YELLOW}🧪 Testing alert functionality for $partition${NC}"
    
    # Create a test alarm state change
    local test_alarm_name="${PROJECT_NAME}-test-alarm-${partition,,}"
    
    # Create temporary test alarm
    aws cloudwatch put-metric-alarm \
        --profile "$profile" \
        --alarm-name "$test_alarm_name" \
        --alarm-description "Test alarm for monitoring deployment" \
        --metric-name "TestMetric" \
        --namespace "Test/${PROJECT_NAME}" \
        --statistic "Average" \
        --period 60 \
        --evaluation-periods 1 \
        --threshold 1 \
        --comparison-operator "GreaterThanThreshold" \
        --treat-missing-data "notBreaching"
    
    # Put test metric data to trigger alarm
    aws cloudwatch put-metric-data \
        --profile "$profile" \
        --namespace "Test/${PROJECT_NAME}" \
        --metric-data MetricName=TestMetric,Value=2,Unit=Count
    
    echo "Test alarm created: $test_alarm_name"
    echo "Check your email and Slack for test notifications in a few minutes"
    
    # Clean up test alarm after 5 minutes
    echo "Test alarm will be automatically cleaned up in 5 minutes"
    (
        sleep 300
        aws cloudwatch delete-alarms \
            --profile "$profile" \
            --alarm-names "$test_alarm_name" 2>/dev/null || true
        echo "Test alarm $test_alarm_name cleaned up"
    ) &
}

# Function to create monitoring dashboard URL
create_dashboard_links() {
    echo -e "${BLUE}📊 CloudWatch Dashboard Links:${NC}"
    echo ""
    
    local govcloud_region="us-gov-west-1"
    local commercial_region="us-east-1"
    
    echo "GovCloud Dashboard:"
    echo "https://${govcloud_region}.console.amazonaws-us-gov.com/cloudwatch/home?region=${govcloud_region}#dashboards:name=${PROJECT_NAME}-vpn-monitoring"
    echo ""
    
    echo "Commercial Dashboard:"
    echo "https://${commercial_region}.console.aws.amazon.com/cloudwatch/home?region=${commercial_region}#dashboards:name=${PROJECT_NAME}-vpn-monitoring"
    echo ""
}

# Function to display monitoring summary
display_monitoring_summary() {
    echo -e "${GREEN}🎉 VPN monitoring deployment completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}📊 Monitoring Components Deployed:${NC}"
    echo "✅ CloudWatch Alarms for VPN tunnel status"
    echo "✅ Cross-partition latency and error rate monitoring"
    echo "✅ VPC endpoint connectivity alarms"
    echo "✅ Lambda function performance monitoring"
    echo "✅ SNS topics for different alert severities"
    echo "✅ Email notifications configured"
    if [ -n "$SLACK_WEBHOOK" ]; then
        echo "✅ Slack notifications configured"
    fi
    echo "✅ CloudWatch dashboards for visualization"
    echo ""
    
    echo -e "${YELLOW}🚨 Alert Thresholds:${NC}"
    echo "• VPN Tunnel Down: 2 consecutive 5-minute periods"
    echo "• High Latency: >5 seconds for 2 consecutive 15-minute periods"
    echo "• High Error Rate: >10 errors in 5 minutes"
    echo "• Lambda Errors: >10 errors in 5 minutes"
    echo "• Lambda Duration: >30 seconds average for 15 minutes"
    echo ""
    
    echo -e "${YELLOW}📈 Key Metrics to Monitor:${NC}"
    echo "• VPN tunnel state (UP/DOWN)"
    echo "• Cross-partition request latency"
    echo "• Request success/failure rates"
    echo "• VPC endpoint connectivity"
    echo "• Lambda function performance"
    echo "• Error rates and patterns"
    echo ""
}

# Main execution
echo -e "${YELLOW}🔍 Checking prerequisites${NC}"
check_profile "$GOVCLOUD_PROFILE"
check_profile "$COMMERCIAL_PROFILE"

# Verify template file exists
if [ ! -f "../infrastructure/vpn-monitoring-alerting.yaml" ]; then
    echo -e "${RED}❌ Monitoring template not found: ../infrastructure/vpn-monitoring-alerting.yaml${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Get alert configuration from user
get_alert_configuration

# Deploy monitoring stacks
GOVCLOUD_MONITORING_STACK="${PROJECT_NAME}-govcloud-monitoring"
COMMERCIAL_MONITORING_STACK="${PROJECT_NAME}-commercial-monitoring"

deploy_monitoring_stack "$GOVCLOUD_PROFILE" "$GOVCLOUD_MONITORING_STACK" "GovCloud"
echo ""

deploy_monitoring_stack "$COMMERCIAL_PROFILE" "$COMMERCIAL_MONITORING_STACK" "Commercial"
echo ""

# Display stack outputs
echo -e "${YELLOW}📊 Stack Outputs:${NC}"
echo ""
echo "=== GovCloud Monitoring Stack Outputs ==="
get_stack_outputs "$GOVCLOUD_PROFILE" "$GOVCLOUD_MONITORING_STACK" "GovCloud"
echo ""
echo "=== Commercial Monitoring Stack Outputs ==="
get_stack_outputs "$COMMERCIAL_PROFILE" "$COMMERCIAL_MONITORING_STACK" "Commercial"
echo ""

# Create dashboard links
create_dashboard_links

# Test alerts (optional)
read -p "Would you like to test alert functionality? (y/N): " TEST_ALERTS
if [[ $TEST_ALERTS =~ ^[Yy]$ ]]; then
    test_alerts "$GOVCLOUD_PROFILE" "GovCloud"
    test_alerts "$COMMERCIAL_PROFILE" "Commercial"
    echo ""
fi

# Display summary
display_monitoring_summary

echo -e "${GREEN}✅ Next steps:${NC}"
echo "1. Check your email for SNS subscription confirmations"
if [ -n "$SLACK_WEBHOOK" ]; then
    echo "2. Verify Slack notifications are working"
fi
echo "3. Access CloudWatch dashboards using the URLs above"
echo "4. Monitor VPN health and performance metrics"
echo "5. Set up additional custom alarms as needed"
echo ""
echo -e "${YELLOW}💡 Pro Tips:${NC}"
echo "• Use CloudWatch Insights to analyze log patterns"
echo "• Set up custom metrics for business-specific KPIs"
echo "• Review and adjust alarm thresholds based on baseline performance"
echo "• Consider setting up automated remediation actions"