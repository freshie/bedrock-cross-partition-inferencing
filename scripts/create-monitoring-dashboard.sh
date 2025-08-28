#!/bin/bash

# Create custom CloudWatch dashboard for dual routing monitoring
# This script creates a comprehensive dashboard with all key metrics

set -e

# Default values
PROJECT_NAME="cross-partition-dual-routing"
ENVIRONMENT="prod"
GOVCLOUD_PROFILE="govcloud"
DASHBOARD_NAME=""
INTERNET_LAMBDA_NAME=""
VPN_LAMBDA_NAME=""
API_GATEWAY_ID=""
API_GATEWAY_STAGE="prod"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Create custom CloudWatch dashboard for dual routing monitoring

Usage: $0 [OPTIONS]

Options:
    --project-name NAME         Project name (default: cross-partition-dual-routing)
    --environment ENV           Environment (dev/staging/prod, default: prod)
    --govcloud-profile PROFILE  AWS CLI profile for GovCloud (default: govcloud)
    --dashboard-name NAME       Custom dashboard name (optional)
    --internet-lambda NAME      Internet Lambda function name (required)
    --vpn-lambda NAME           VPN Lambda function name (required)
    --api-gateway-id ID         API Gateway ID (required)
    --api-gateway-stage STAGE   API Gateway stage name (default: prod)
    --help                     Show this help message

Examples:
    # Create dashboard
    $0 --internet-lambda internet-lambda-function \\
       --vpn-lambda vpn-lambda-function \\
       --api-gateway-id abcd123456

EOF
}

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
        --dashboard-name)
            DASHBOARD_NAME="$2"
            shift 2
            ;;
        --internet-lambda)
            INTERNET_LAMBDA_NAME="$2"
            shift 2
            ;;
        --vpn-lambda)
            VPN_LAMBDA_NAME="$2"
            shift 2
            ;;
        --api-gateway-id)
            API_GATEWAY_ID="$2"
            shift 2
            ;;
        --api-gateway-stage)
            API_GATEWAY_STAGE="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$INTERNET_LAMBDA_NAME" ]]; then
    log_error "Internet Lambda function name is required. Use --internet-lambda parameter."
    exit 1
fi

if [[ -z "$VPN_LAMBDA_NAME" ]]; then
    log_error "VPN Lambda function name is required. Use --vpn-lambda parameter."
    exit 1
fi

if [[ -z "$API_GATEWAY_ID" ]]; then
    log_error "API Gateway ID is required. Use --api-gateway-id parameter."
    exit 1
fi

# Set dashboard name if not provided
if [[ -z "$DASHBOARD_NAME" ]]; then
    DASHBOARD_NAME="${PROJECT_NAME}-comprehensive-${ENVIRONMENT}"
fi

# Validate AWS CLI profile
if ! aws sts get-caller-identity --profile "$GOVCLOUD_PROFILE" >/dev/null 2>&1; then
    log_error "Cannot access AWS with profile '$GOVCLOUD_PROFILE'. Please check your AWS configuration."
    exit 1
fi

# Get AWS region
AWS_REGION=$(aws configure get region --profile "$GOVCLOUD_PROFILE")
if [[ -z "$AWS_REGION" ]]; then
    AWS_REGION="us-gov-west-1"
    log_warning "No region configured for profile '$GOVCLOUD_PROFILE', using default: $AWS_REGION"
fi

log_info "Creating comprehensive CloudWatch dashboard..."
log_info "  Dashboard Name: $DASHBOARD_NAME"
log_info "  Internet Lambda: $INTERNET_LAMBDA_NAME"
log_info "  VPN Lambda: $VPN_LAMBDA_NAME"
log_info "  API Gateway: $API_GATEWAY_ID"
log_info "  Region: $AWS_REGION"

# Create comprehensive dashboard JSON
DASHBOARD_BODY=$(cat << EOF
{
  "widgets": [
    {
      "type": "text",
      "x": 0,
      "y": 0,
      "width": 24,
      "height": 2,
      "properties": {
        "markdown": "# Dual Routing Cross-Partition Inference Dashboard\\n\\n**Environment:** ${ENVIRONMENT} | **Project:** ${PROJECT_NAME} | **Last Updated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 2,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting", "CrossPartitionRequests", "RoutingMethod", "internet", "Success", "true", { "label": "Internet Success" } ],
          [ "...", "vpn", ".", ".", { "label": "VPN Success" } ],
          [ "...", "internet", ".", "false", { "label": "Internet Errors" } ],
          [ "...", "vpn", ".", ".", { "label": "VPN Errors" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Request Volume by Routing Method",
        "period": 300,
        "stat": "Sum",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 8,
      "y": 2,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting", "CrossPartitionLatency", "RoutingMethod", "internet", { "label": "Internet Avg" } ],
          [ "...", "vpn", { "label": "VPN Avg" } ],
          [ "CrossPartition/DualRouting/Analytics", "LatencyP95", "RoutingMethod", "internet", { "label": "Internet P95" } ],
          [ "...", "vpn", { "label": "VPN P95" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Response Latency Comparison",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 16,
      "y": 2,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Analytics", "SuccessRatePercentage", "RoutingMethod", "internet", { "label": "Internet Success Rate" } ],
          [ "...", "vpn", { "label": "VPN Success Rate" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Success Rate Percentage",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 90,
            "max": 100
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 8,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Errors", "ErrorCount", "RoutingMethod", "internet", "ErrorCategory", "authentication", { "label": "Internet Auth" } ],
          [ "...", "authorization", { "label": "Internet Authz" } ],
          [ "...", "validation", { "label": "Internet Validation" } ],
          [ "...", "network", { "label": "Internet Network" } ],
          [ "...", "service", { "label": "Internet Service" } ]
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${AWS_REGION}",
        "title": "Internet Routing Errors by Category",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 8,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Errors", "ErrorCount", "RoutingMethod", "vpn", "ErrorCategory", "authentication", { "label": "VPN Auth" } ],
          [ "...", "authorization", { "label": "VPN Authz" } ],
          [ "...", "validation", { "label": "VPN Validation" } ],
          [ "...", "vpn_specific", { "label": "VPN Specific" } ],
          [ "...", "network", { "label": "VPN Network" } ],
          [ "...", "service", { "label": "VPN Service" } ]
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${AWS_REGION}",
        "title": "VPN Routing Errors by Category",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 14,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting", "VPCEndpointHealth", "RoutingMethod", "vpn", "EndpointName", "secrets", { "label": "Secrets Manager" } ],
          [ "...", "dynamodb", { "label": "DynamoDB" } ],
          [ "...", "cloudwatch", { "label": "CloudWatch" } ],
          [ "...", "vpn_tunnel", { "label": "VPN Tunnel" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "VPC Endpoint Health Status",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 0,
            "max": 1
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 8,
      "y": 14,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Analytics", "TrafficDistribution", "RoutingMethod", "internet", { "label": "Internet Traffic %" } ],
          [ "...", "vpn", { "label": "VPN Traffic %" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Traffic Distribution",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100
          }
        }
      }
    },
    {
      "type": "metric",
      "x": 16,
      "y": 14,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Errors", "RetryableErrors", "RoutingMethod", "internet", "ErrorCategory", "network", { "label": "Internet Network" } ],
          [ "...", "service", { "label": "Internet Service" } ],
          [ "...", "vpn", ".", "vpn_specific", { "label": "VPN Specific" } ],
          [ "...", "network", { "label": "VPN Network" } ],
          [ "...", "service", { "label": "VPN Service" } ]
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${AWS_REGION}",
        "title": "Retryable Errors",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 20,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/Lambda", "Duration", "FunctionName", "${INTERNET_LAMBDA_NAME}", { "label": "Internet Lambda Duration" } ],
          [ "...", "${VPN_LAMBDA_NAME}", { "label": "VPN Lambda Duration" } ],
          [ ".", "Invocations", ".", "${INTERNET_LAMBDA_NAME}", { "label": "Internet Lambda Invocations" } ],
          [ "...", "${VPN_LAMBDA_NAME}", { "label": "VPN Lambda Invocations" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Lambda Function Performance",
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 20,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/Lambda", "Errors", "FunctionName", "${INTERNET_LAMBDA_NAME}", { "label": "Internet Lambda Errors" } ],
          [ "...", "${VPN_LAMBDA_NAME}", { "label": "VPN Lambda Errors" } ],
          [ ".", "Throttles", ".", "${INTERNET_LAMBDA_NAME}", { "label": "Internet Lambda Throttles" } ],
          [ "...", "${VPN_LAMBDA_NAME}", { "label": "VPN Lambda Throttles" } ],
          [ ".", "ConcurrentExecutions", ".", "${INTERNET_LAMBDA_NAME}", { "label": "Internet Concurrent" } ],
          [ "...", "${VPN_LAMBDA_NAME}", { "label": "VPN Concurrent" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Lambda Function Health",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 26,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/ApiGateway", "Count", "ApiName", "${API_GATEWAY_ID}", "Stage", "${API_GATEWAY_STAGE}", { "label": "Total Requests" } ],
          [ ".", "4XXError", ".", ".", ".", ".", { "label": "4XX Errors" } ],
          [ ".", "5XXError", ".", ".", ".", ".", { "label": "5XX Errors" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "API Gateway Request Volume",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 26,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/ApiGateway", "Latency", "ApiName", "${API_GATEWAY_ID}", "Stage", "${API_GATEWAY_STAGE}", { "label": "API Gateway Latency" } ],
          [ ".", "IntegrationLatency", ".", ".", ".", ".", { "label": "Integration Latency" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "API Gateway Latency",
        "period": 300,
        "stat": "Average"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 32,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/lambda/${INTERNET_LAMBDA_NAME}' | SOURCE '/aws/lambda/${VPN_LAMBDA_NAME}'\\n| fields @timestamp, @message\\n| filter @message like /ERROR/\\n| sort @timestamp desc\\n| limit 20",
        "region": "${AWS_REGION}",
        "title": "Recent Errors from Lambda Functions",
        "view": "table"
      }
    }
  ]
}
EOF
)

# Create the dashboard
log_info "Creating CloudWatch dashboard: $DASHBOARD_NAME"

aws cloudwatch put-dashboard \
    --dashboard-name "$DASHBOARD_NAME" \
    --dashboard-body "$DASHBOARD_BODY" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION"

# Get dashboard URL
DASHBOARD_URL="https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"

log_success "CloudWatch dashboard created successfully!"
log_info ""
log_info "Dashboard Details:"
log_info "  Name: $DASHBOARD_NAME"
log_info "  URL: $DASHBOARD_URL"
log_info ""
log_info "Dashboard Features:"
log_info "✓ Request volume comparison (Internet vs VPN)"
log_info "✓ Latency analysis with percentiles"
log_info "✓ Success rate monitoring"
log_info "✓ Error categorization and trends"
log_info "✓ VPC endpoint health status"
log_info "✓ Traffic distribution analysis"
log_info "✓ Lambda function performance metrics"
log_info "✓ API Gateway metrics"
log_info "✓ Recent error log analysis"
log_info ""
log_info "Next steps:"
log_info "1. Access the dashboard URL above"
log_info "2. Customize time ranges and refresh intervals"
log_info "3. Set up additional custom metrics if needed"
log_info "4. Share dashboard with your team"