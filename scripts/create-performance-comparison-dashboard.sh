#!/bin/bash

# Create performance comparison dashboard for dual routing methods
# This script creates detailed performance analysis charts

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
Create performance comparison dashboard for dual routing methods

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
    # Create performance comparison dashboard
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
    DASHBOARD_NAME="${PROJECT_NAME}-performance-comparison-${ENVIRONMENT}"
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

log_info "Creating performance comparison dashboard..."
log_info "  Dashboard Name: $DASHBOARD_NAME"
log_info "  Internet Lambda: $INTERNET_LAMBDA_NAME"
log_info "  VPN Lambda: $VPN_LAMBDA_NAME"
log_info "  API Gateway: $API_GATEWAY_ID"
log_info "  Region: $AWS_REGION"

# Create performance comparison dashboard JSON
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
        "markdown": "# Dual Routing Performance Comparison Dashboard\\n\\n**Environment:** ${ENVIRONMENT} | **Project:** ${PROJECT_NAME} | **Last Updated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")\\n\\nThis dashboard provides detailed performance comparison between Internet and VPN routing methods."
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 2,
      "width": 12,
      "height": 8,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting", "CrossPartitionLatency", "RoutingMethod", "internet", { "label": "Internet Avg Latency", "color": "#1f77b4" } ],
          [ "...", "vpn", { "label": "VPN Avg Latency", "color": "#ff7f0e" } ],
          [ "CrossPartition/DualRouting/Analytics", "LatencyP50", "RoutingMethod", "internet", { "label": "Internet P50", "color": "#2ca02c" } ],
          [ "...", "vpn", { "label": "VPN P50", "color": "#d62728" } ],
          [ ".", "LatencyP95", "RoutingMethod", "internet", { "label": "Internet P95", "color": "#9467bd" } ],
          [ "...", "vpn", { "label": "VPN P95", "color": "#8c564b" } ],
          [ ".", "LatencyP99", "RoutingMethod", "internet", { "label": "Internet P99", "color": "#e377c2" } ],
          [ "...", "vpn", { "label": "VPN P99", "color": "#7f7f7f" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Latency Comparison - All Percentiles",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 0
          }
        },
        "annotations": {
          "horizontal": [
            {
              "label": "Target SLA (5s)",
              "value": 5000
            },
            {
              "label": "Warning Threshold (10s)",
              "value": 10000
            }
          ]
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 2,
      "width": 12,
      "height": 8,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting", "CrossPartitionRequests", "RoutingMethod", "internet", "Success", "true", { "label": "Internet Successful", "color": "#2ca02c" } ],
          [ "...", "vpn", ".", ".", { "label": "VPN Successful", "color": "#1f77b4" } ],
          [ "...", "internet", ".", "false", { "label": "Internet Failed", "color": "#d62728" } ],
          [ "...", "vpn", ".", ".", { "label": "VPN Failed", "color": "#ff7f0e" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Request Volume and Success Rate Comparison",
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
      "x": 0,
      "y": 10,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Analytics", "ThroughputRPS", "RoutingMethod", "internet", { "label": "Internet RPS" } ],
          [ "...", "vpn", { "label": "VPN RPS" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Throughput Comparison (Requests/Second)",
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
      "x": 8,
      "y": 10,
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
        "title": "Success Rate Comparison (%)",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 95,
            "max": 100
          }
        },
        "annotations": {
          "horizontal": [
            {
              "label": "SLA Target (99%)",
              "value": 99
            },
            {
              "label": "Warning (95%)",
              "value": 95
            }
          ]
        }
      }
    },
    {
      "type": "metric",
      "x": 16,
      "y": 10,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Analytics", "ErrorRatePercentage", "RoutingMethod", "internet", { "label": "Internet Error Rate" } ],
          [ "...", "vpn", { "label": "VPN Error Rate" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Error Rate Comparison (%)",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 0,
            "max": 5
          }
        },
        "annotations": {
          "horizontal": [
            {
              "label": "Error Budget (1%)",
              "value": 1
            },
            {
              "label": "Critical (5%)",
              "value": 5
            }
          ]
        }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 16,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/Lambda", "Duration", "FunctionName", "${INTERNET_LAMBDA_NAME}", { "label": "Internet Lambda Duration", "color": "#1f77b4" } ],
          [ "...", "${VPN_LAMBDA_NAME}", { "label": "VPN Lambda Duration", "color": "#ff7f0e" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Lambda Function Duration Comparison",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 0
          }
        },
        "annotations": {
          "horizontal": [
            {
              "label": "Internet Timeout (30s)",
              "value": 30000
            },
            {
              "label": "VPN Timeout (45s)",
              "value": 45000
            }
          ]
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 16,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/Lambda", "ConcurrentExecutions", "FunctionName", "${INTERNET_LAMBDA_NAME}", { "label": "Internet Concurrent" } ],
          [ "...", "${VPN_LAMBDA_NAME}", { "label": "VPN Concurrent" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Lambda Concurrent Executions Comparison",
        "period": 300,
        "stat": "Maximum"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 22,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Analytics", "CostPerRequest", "RoutingMethod", "internet", { "label": "Internet Cost/Request" } ],
          [ "...", "vpn", { "label": "VPN Cost/Request" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Cost Per Request Comparison",
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
      "x": 8,
      "y": 22,
      "width": 8,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Analytics", "DataTransferMB", "RoutingMethod", "internet", { "label": "Internet Data Transfer" } ],
          [ "...", "vpn", { "label": "VPN Data Transfer" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Data Transfer Comparison (MB)",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "metric",
      "x": 16,
      "y": 22,
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
      "x": 0,
      "y": 28,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Analytics", "LatencyDifference", { "label": "VPN vs Internet Latency Difference (ms)" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Latency Difference (VPN - Internet)",
        "period": 300,
        "stat": "Average",
        "annotations": {
          "horizontal": [
            {
              "label": "No Difference",
              "value": 0
            }
          ]
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 28,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Analytics", "ReliabilityScore", "RoutingMethod", "internet", { "label": "Internet Reliability Score" } ],
          [ "...", "vpn", { "label": "VPN Reliability Score" } ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Reliability Score Comparison (0-100)",
        "period": 300,
        "stat": "Average",
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100
          }
        },
        "annotations": {
          "horizontal": [
            {
              "label": "Excellent (95+)",
              "value": 95
            },
            {
              "label": "Good (90+)",
              "value": 90
            },
            {
              "label": "Poor (<80)",
              "value": 80
            }
          ]
        }
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 34,
      "width": 24,
      "height": 6,
      "properties": {
        "metrics": [
          [ "CrossPartition/DualRouting/Errors", "ErrorCount", "RoutingMethod", "internet", "ErrorCategory", "authentication", { "label": "Internet Auth Errors" } ],
          [ "...", "authorization", { "label": "Internet Authz Errors" } ],
          [ "...", "validation", { "label": "Internet Validation Errors" } ],
          [ "...", "network", { "label": "Internet Network Errors" } ],
          [ "...", "service", { "label": "Internet Service Errors" } ],
          [ "...", "vpn", ".", "authentication", { "label": "VPN Auth Errors" } ],
          [ "...", "authorization", { "label": "VPN Authz Errors" } ],
          [ "...", "validation", { "label": "VPN Validation Errors" } ],
          [ "...", "vpn_specific", { "label": "VPN Specific Errors" } ],
          [ "...", "network", { "label": "VPN Network Errors" } ],
          [ "...", "service", { "label": "VPN Service Errors" } ]
        ],
        "view": "timeSeries",
        "stacked": true,
        "region": "${AWS_REGION}",
        "title": "Error Category Comparison",
        "period": 300,
        "stat": "Sum"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 40,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/lambda/${INTERNET_LAMBDA_NAME}' | SOURCE '/aws/lambda/${VPN_LAMBDA_NAME}'\\n| fields @timestamp, @message, @logStream\\n| filter @message like /PERFORMANCE/\\n| sort @timestamp desc\\n| limit 50",
        "region": "${AWS_REGION}",
        "title": "Performance Log Analysis",
        "view": "table"
      }
    }
  ]
}
EOF
)

# Create the dashboard
log_info "Creating performance comparison dashboard: $DASHBOARD_NAME"

aws cloudwatch put-dashboard \
    --dashboard-name "$DASHBOARD_NAME" \
    --dashboard-body "$DASHBOARD_BODY" \
    --profile "$GOVCLOUD_PROFILE" \
    --region "$AWS_REGION"

# Get dashboard URL
DASHBOARD_URL="https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"

log_success "Performance comparison dashboard created successfully!"
log_info ""
log_info "Dashboard Details:"
log_info "  Name: $DASHBOARD_NAME"
log_info "  URL: $DASHBOARD_URL"
log_info ""
log_info "Performance Comparison Features:"
log_info "✓ Latency comparison with all percentiles (P50, P95, P99)"
log_info "✓ Request volume and success rate analysis"
log_info "✓ Throughput comparison (RPS)"
log_info "✓ Error rate percentage tracking"
log_info "✓ Lambda function duration comparison"
log_info "✓ Concurrent execution analysis"
log_info "✓ Cost per request comparison"
log_info "✓ Data transfer analysis"
log_info "✓ Traffic distribution monitoring"
log_info "✓ Latency difference calculation"
log_info "✓ Reliability score comparison"
log_info "✓ Error category breakdown"
log_info "✓ Performance log analysis"
log_info ""
log_info "Key Performance Insights:"
log_info "• Compare latency characteristics between routing methods"
log_info "• Analyze cost-effectiveness of each routing approach"
log_info "• Monitor reliability and error patterns"
log_info "• Track traffic distribution and usage patterns"
log_info "• Identify performance bottlenecks and optimization opportunities"
log_info ""
log_info "Next steps:"
log_info "1. Access the dashboard URL above"
log_info "2. Set appropriate time ranges for analysis"
log_info "3. Use insights to optimize routing decisions"
log_info "4. Share performance data with stakeholders"