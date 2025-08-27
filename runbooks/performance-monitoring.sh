#!/bin/bash

# VPN Performance Monitoring and Capacity Planning
# This script provides automated performance monitoring and capacity planning

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

# Performance thresholds
LAMBDA_DURATION_THRESHOLD=5000  # 5 seconds
VPN_LATENCY_THRESHOLD=100       # 100ms
ERROR_RATE_THRESHOLD=5          # 5%
TUNNEL_UTILIZATION_THRESHOLD=80 # 80%

show_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  report          Generate performance report"
    echo "  monitor         Continuous performance monitoring"
    echo "  capacity        Capacity planning analysis"
    echo "  optimize        Performance optimization recommendations"
    echo "  baseline        Establish performance baselines"
    echo ""
    echo "Options:"
    echo "  --period HOURS     Analysis period in hours (default: 24)"
    echo "  --output-dir DIR   Output directory (default: ./reports)"
    echo "  --format FORMAT    Output format (json|csv|table, default: table)"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 report --period 168  # Weekly report"
    echo "  $0 monitor              # Continuous monitoring"
    echo "  $0 capacity --period 720 # Monthly capacity analysis"
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    show_usage
    exit 1
fi

COMMAND="$1"
shift

PERIOD_HOURS=24
OUTPUT_DIR="./reports"
OUTPUT_FORMAT="table"

while [[ $# -gt 0 ]]; do
    case $1 in
        --period)
            PERIOD_HOURS="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
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

# Create output directory
mkdir -p "$OUTPUT_DIR"
REPORT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT_DIR="$OUTPUT_DIR/performance-$REPORT_TIMESTAMP"
mkdir -p "$REPORT_DIR"

echo -e "${BLUE}📊 VPN Performance Monitoring${NC}"
echo -e "${BLUE}Command: $COMMAND${NC}"
echo -e "${BLUE}Period: $PERIOD_HOURS hours${NC}"
echo -e "${BLUE}Output: $REPORT_DIR${NC}"
echo ""

# Function to get CloudWatch metrics
get_metric_statistics() {
    local namespace=$1
    local metric_name=$2
    local dimensions=$3
    local statistic=$4
    local profile=$5
    local region=$6
    
    aws cloudwatch get-metric-statistics \
        --namespace "$namespace" \
        --metric-name "$metric_name" \
        --dimensions "$dimensions" \
        --start-time $(date -u -d "${PERIOD_HOURS} hours ago" +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 3600 \
        --statistics "$statistic" \
        --profile "$profile" \
        --region "$region" \
        --output json
}

# Function to generate performance report
generate_performance_report() {
    echo -e "${YELLOW}📈 Generating performance report...${NC}"
    
    # Lambda performance metrics
    echo -e "${BLUE}Lambda Performance:${NC}"
    
    LAMBDA_DURATION=$(get_metric_statistics \
        "AWS/Lambda" \
        "Duration" \
        "Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME" \
        "Average" \
        "$GOVCLOUD_PROFILE" \
        "us-gov-west-1")
    
    LAMBDA_INVOCATIONS=$(get_metric_statistics \
        "AWS/Lambda" \
        "Invocations" \
        "Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME" \
        "Sum" \
        "$GOVCLOUD_PROFILE" \
        "us-gov-west-1")
    
    LAMBDA_ERRORS=$(get_metric_statistics \
        "AWS/Lambda" \
        "Errors" \
        "Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME" \
        "Sum" \
        "$GOVCLOUD_PROFILE" \
        "us-gov-west-1")
    
    # Calculate averages
    AVG_DURATION=$(echo "$LAMBDA_DURATION" | jq -r '.Datapoints | map(.Average) | add / length')
    TOTAL_INVOCATIONS=$(echo "$LAMBDA_INVOCATIONS" | jq -r '.Datapoints | map(.Sum) | add')
    TOTAL_ERRORS=$(echo "$LAMBDA_ERRORS" | jq -r '.Datapoints | map(.Sum) | add')
    
    if [ "$TOTAL_INVOCATIONS" != "null" ] && [ "$TOTAL_INVOCATIONS" != "0" ]; then
        ERROR_RATE=$(echo "scale=2; $TOTAL_ERRORS * 100 / $TOTAL_INVOCATIONS" | bc)
    else
        ERROR_RATE=0
    fi
    
    echo "  Average Duration: ${AVG_DURATION}ms"
    echo "  Total Invocations: $TOTAL_INVOCATIONS"
    echo "  Total Errors: $TOTAL_ERRORS"
    echo "  Error Rate: ${ERROR_RATE}%"
    
    # VPN performance metrics
    echo -e "${BLUE}VPN Performance:${NC}"
    
    VPN_LATENCY=$(get_metric_statistics \
        "AWS/VPN" \
        "TunnelLatency" \
        "Name=VpnId,Value=$GOVCLOUD_VPN_CONNECTION_ID" \
        "Average" \
        "$GOVCLOUD_PROFILE" \
        "us-gov-west-1")
    
    VPN_PACKET_DROPS=$(get_metric_statistics \
        "AWS/VPN" \
        "PacketDropCount" \
        "Name=VpnId,Value=$GOVCLOUD_VPN_CONNECTION_ID" \
        "Sum" \
        "$GOVCLOUD_PROFILE" \
        "us-gov-west-1")
    
    AVG_LATENCY=$(echo "$VPN_LATENCY" | jq -r '.Datapoints | map(.Average) | add / length')
    TOTAL_DROPS=$(echo "$VPN_PACKET_DROPS" | jq -r '.Datapoints | map(.Sum) | add')
    
    echo "  Average Latency: ${AVG_LATENCY}ms"
    echo "  Total Packet Drops: $TOTAL_DROPS"
    
    # Performance assessment
    echo -e "${BLUE}Performance Assessment:${NC}"
    
    ISSUES=0
    
    if (( $(echo "$AVG_DURATION > $LAMBDA_DURATION_THRESHOLD" | bc -l) )); then
        echo -e "${RED}⚠️ Lambda duration exceeds threshold (${AVG_DURATION}ms > ${LAMBDA_DURATION_THRESHOLD}ms)${NC}"
        ((ISSUES++))
    else
        echo -e "${GREEN}✅ Lambda duration within acceptable range${NC}"
    fi
    
    if (( $(echo "$AVG_LATENCY > $VPN_LATENCY_THRESHOLD" | bc -l) )); then
        echo -e "${RED}⚠️ VPN latency exceeds threshold (${AVG_LATENCY}ms > ${VPN_LATENCY_THRESHOLD}ms)${NC}"
        ((ISSUES++))
    else
        echo -e "${GREEN}✅ VPN latency within acceptable range${NC}"
    fi
    
    if (( $(echo "$ERROR_RATE > $ERROR_RATE_THRESHOLD" | bc -l) )); then
        echo -e "${RED}⚠️ Error rate exceeds threshold (${ERROR_RATE}% > ${ERROR_RATE_THRESHOLD}%)${NC}"
        ((ISSUES++))
    else
        echo -e "${GREEN}✅ Error rate within acceptable range${NC}"
    fi
    
    # Save detailed report
    cat > "$REPORT_DIR/performance-summary.json" << EOF
{
    "report_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "period_hours": $PERIOD_HOURS,
    "lambda_metrics": {
        "average_duration_ms": $AVG_DURATION,
        "total_invocations": $TOTAL_INVOCATIONS,
        "total_errors": $TOTAL_ERRORS,
        "error_rate_percent": $ERROR_RATE
    },
    "vpn_metrics": {
        "average_latency_ms": $AVG_LATENCY,
        "total_packet_drops": $TOTAL_DROPS
    },
    "performance_issues": $ISSUES,
    "thresholds": {
        "lambda_duration_ms": $LAMBDA_DURATION_THRESHOLD,
        "vpn_latency_ms": $VPN_LATENCY_THRESHOLD,
        "error_rate_percent": $ERROR_RATE_THRESHOLD
    }
}
EOF
    
    echo "$LAMBDA_DURATION" > "$REPORT_DIR/lambda-duration-raw.json"
    echo "$VPN_LATENCY" > "$REPORT_DIR/vpn-latency-raw.json"
    
    echo -e "${GREEN}✅ Performance report generated${NC}"
    return $ISSUES
}

# Function for continuous monitoring
continuous_monitoring() {
    echo -e "${YELLOW}👀 Starting continuous performance monitoring...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    echo ""
    
    local iteration=1
    
    while true; do
        clear
        echo -e "${BLUE}🔄 Performance Monitor - Iteration $iteration - $(date)${NC}"
        echo "=================================================================="
        
        # Quick performance check
        PERIOD_HOURS=1  # Check last hour for continuous monitoring
        generate_performance_report
        
        # Check for immediate issues
        if [ $? -gt 0 ]; then
            echo -e "${RED}🚨 Performance issues detected!${NC}"
            
            # Send alert (placeholder - implement actual alerting)
            echo "Alert: Performance degradation detected at $(date)" >> "$OUTPUT_DIR/performance-alerts.log"
        fi
        
        echo ""
        echo -e "${BLUE}Next check in 5 minutes... (Iteration $((iteration + 1)))${NC}"
        
        sleep 300  # 5 minutes
        ((iteration++))
    done
}

# Function for capacity planning analysis
capacity_planning() {
    echo -e "${YELLOW}📊 Performing capacity planning analysis...${NC}"
    
    # Analyze trends over the specified period
    echo -e "${BLUE}Analyzing usage trends over $PERIOD_HOURS hours...${NC}"
    
    # Get detailed metrics with smaller periods for trend analysis
    LAMBDA_DURATION_TREND=$(aws cloudwatch get-metric-statistics \
        --namespace "AWS/Lambda" \
        --metric-name "Duration" \
        --dimensions "Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME" \
        --start-time $(date -u -d "${PERIOD_HOURS} hours ago" +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 3600 \
        --statistics "Average,Maximum" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json)
    
    LAMBDA_INVOCATIONS_TREND=$(aws cloudwatch get-metric-statistics \
        --namespace "AWS/Lambda" \
        --metric-name "Invocations" \
        --dimensions "Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME" \
        --start-time $(date -u -d "${PERIOD_HOURS} hours ago" +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 3600 \
        --statistics "Sum" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --output json)
    
    # Calculate trends
    MAX_INVOCATIONS=$(echo "$LAMBDA_INVOCATIONS_TREND" | jq -r '.Datapoints | map(.Sum) | max')
    AVG_INVOCATIONS=$(echo "$LAMBDA_INVOCATIONS_TREND" | jq -r '.Datapoints | map(.Sum) | add / length')
    MAX_DURATION=$(echo "$LAMBDA_DURATION_TREND" | jq -r '.Datapoints | map(.Maximum) | max')
    
    echo "  Peak Invocations/hour: $MAX_INVOCATIONS"
    echo "  Average Invocations/hour: $AVG_INVOCATIONS"
    echo "  Peak Duration: ${MAX_DURATION}ms"
    
    # Capacity recommendations
    echo -e "${BLUE}Capacity Recommendations:${NC}"
    
    # Lambda concurrency recommendations
    if (( $(echo "$MAX_INVOCATIONS > 100" | bc -l) )); then
        RECOMMENDED_CONCURRENCY=$(echo "scale=0; $MAX_INVOCATIONS / 10" | bc)
        echo "  Consider provisioned concurrency: $RECOMMENDED_CONCURRENCY"
    fi
    
    # Memory recommendations
    if (( $(echo "$MAX_DURATION > 3000" | bc -l) )); then
        echo "  Consider increasing Lambda memory allocation"
    fi
    
    # VPN bandwidth analysis
    echo -e "${BLUE}VPN Bandwidth Analysis:${NC}"
    
    # Estimate bandwidth usage (simplified calculation)
    ESTIMATED_BANDWIDTH_MBPS=$(echo "scale=2; $MAX_INVOCATIONS * 0.1" | bc)  # Assume 0.1 MB per request
    VPN_CAPACITY_MBPS=1250  # 1.25 Gbps per tunnel
    UTILIZATION_PERCENT=$(echo "scale=2; $ESTIMATED_BANDWIDTH_MBPS * 100 / $VPN_CAPACITY_MBPS" | bc)
    
    echo "  Estimated peak bandwidth: ${ESTIMATED_BANDWIDTH_MBPS} Mbps"
    echo "  VPN capacity per tunnel: ${VPN_CAPACITY_MBPS} Mbps"
    echo "  Estimated utilization: ${UTILIZATION_PERCENT}%"
    
    if (( $(echo "$UTILIZATION_PERCENT > $TUNNEL_UTILIZATION_THRESHOLD" | bc -l) )); then
        echo -e "${RED}⚠️ VPN utilization approaching capacity limits${NC}"
    else
        echo -e "${GREEN}✅ VPN capacity sufficient for current load${NC}"
    fi
    
    # Save capacity planning report
    cat > "$REPORT_DIR/capacity-planning.json" << EOF
{
    "analysis_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "period_hours": $PERIOD_HOURS,
    "lambda_capacity": {
        "peak_invocations_per_hour": $MAX_INVOCATIONS,
        "average_invocations_per_hour": $AVG_INVOCATIONS,
        "peak_duration_ms": $MAX_DURATION,
        "recommended_concurrency": ${RECOMMENDED_CONCURRENCY:-0}
    },
    "vpn_capacity": {
        "estimated_peak_bandwidth_mbps": $ESTIMATED_BANDWIDTH_MBPS,
        "tunnel_capacity_mbps": $VPN_CAPACITY_MBPS,
        "utilization_percent": $UTILIZATION_PERCENT
    },
    "recommendations": [
        $([ "$RECOMMENDED_CONCURRENCY" ] && echo "\"Enable provisioned concurrency: $RECOMMENDED_CONCURRENCY\"," || echo "")
        $([ "$(echo "$MAX_DURATION > 3000" | bc -l)" = "1" ] && echo "\"Increase Lambda memory allocation\"," || echo "")
        $([ "$(echo "$UTILIZATION_PERCENT > $TUNNEL_UTILIZATION_THRESHOLD" | bc -l)" = "1" ] && echo "\"Monitor VPN bandwidth usage\"" || echo "\"VPN capacity is sufficient\"")
    ]
}
EOF
    
    echo -e "${GREEN}✅ Capacity planning analysis completed${NC}"
}

# Function to provide optimization recommendations
performance_optimization() {
    echo -e "${YELLOW}🚀 Generating performance optimization recommendations...${NC}"
    
    # Analyze current performance
    generate_performance_report > /dev/null
    
    echo -e "${BLUE}Optimization Recommendations:${NC}"
    
    # Lambda optimizations
    echo -e "${BLUE}Lambda Function Optimizations:${NC}"
    
    CURRENT_MEMORY=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query 'MemorySize' \
        --output text)
    
    CURRENT_TIMEOUT=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query 'Timeout' \
        --output text)
    
    echo "  Current Memory: ${CURRENT_MEMORY}MB"
    echo "  Current Timeout: ${CURRENT_TIMEOUT}s"
    
    if [ "$CURRENT_MEMORY" -lt 512 ]; then
        echo -e "${YELLOW}  💡 Consider increasing memory to 512MB for better performance${NC}"
    fi
    
    if [ "$CURRENT_TIMEOUT" -lt 30 ]; then
        echo -e "${YELLOW}  💡 Consider increasing timeout to 30s for cross-partition calls${NC}"
    fi
    
    # VPN optimizations
    echo -e "${BLUE}VPN Optimizations:${NC}"
    echo "  💡 Implement connection pooling in Lambda function"
    echo "  💡 Use response caching for frequently requested data"
    echo "  💡 Optimize payload compression"
    echo "  💡 Monitor and tune BGP routing"
    
    # Cost optimizations
    echo -e "${BLUE}Cost Optimizations:${NC}"
    echo "  💡 Right-size Lambda memory based on actual usage"
    echo "  💡 Implement lifecycle policies for CloudWatch logs"
    echo "  💡 Monitor VPC endpoint data processing charges"
    echo "  💡 Use reserved capacity for predictable workloads"
    
    echo -e "${GREEN}✅ Optimization recommendations generated${NC}"
}

# Function to establish performance baselines
establish_baselines() {
    echo -e "${YELLOW}📏 Establishing performance baselines...${NC}"
    
    # Use a longer period for baseline establishment
    BASELINE_PERIOD=168  # 1 week
    
    echo -e "${BLUE}Collecting baseline data over $BASELINE_PERIOD hours...${NC}"
    
    # Get comprehensive metrics for baseline
    BASELINE_DURATION=$(get_metric_statistics \
        "AWS/Lambda" \
        "Duration" \
        "Name=FunctionName,Value=$LAMBDA_FUNCTION_NAME" \
        "Average" \
        "$GOVCLOUD_PROFILE" \
        "us-gov-west-1")
    
    BASELINE_LATENCY=$(get_metric_statistics \
        "AWS/VPN" \
        "TunnelLatency" \
        "Name=VpnId,Value=$GOVCLOUD_VPN_CONNECTION_ID" \
        "Average" \
        "$GOVCLOUD_PROFILE" \
        "us-gov-west-1")
    
    # Calculate baseline values
    BASELINE_AVG_DURATION=$(echo "$BASELINE_DURATION" | jq -r '.Datapoints | map(.Average) | add / length')
    BASELINE_P95_DURATION=$(echo "$BASELINE_DURATION" | jq -r '.Datapoints | map(.Average) | sort | .[length * 0.95 | floor]')
    BASELINE_AVG_LATENCY=$(echo "$BASELINE_LATENCY" | jq -r '.Datapoints | map(.Average) | add / length')
    BASELINE_P95_LATENCY=$(echo "$BASELINE_LATENCY" | jq -r '.Datapoints | map(.Average) | sort | .[length * 0.95 | floor]')
    
    echo "  Baseline Average Duration: ${BASELINE_AVG_DURATION}ms"
    echo "  Baseline P95 Duration: ${BASELINE_P95_DURATION}ms"
    echo "  Baseline Average Latency: ${BASELINE_AVG_LATENCY}ms"
    echo "  Baseline P95 Latency: ${BASELINE_P95_LATENCY}ms"
    
    # Save baselines
    cat > "$OUTPUT_DIR/performance-baselines.json" << EOF
{
    "baseline_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
    "baseline_period_hours": $BASELINE_PERIOD,
    "lambda_baselines": {
        "average_duration_ms": $BASELINE_AVG_DURATION,
        "p95_duration_ms": $BASELINE_P95_DURATION
    },
    "vpn_baselines": {
        "average_latency_ms": $BASELINE_AVG_LATENCY,
        "p95_latency_ms": $BASELINE_P95_LATENCY
    },
    "recommended_thresholds": {
        "lambda_duration_alert_ms": $(echo "$BASELINE_P95_DURATION * 1.5" | bc),
        "vpn_latency_alert_ms": $(echo "$BASELINE_P95_LATENCY * 1.5" | bc)
    }
}
EOF
    
    echo -e "${GREEN}✅ Performance baselines established${NC}"
    echo -e "${BLUE}Baselines saved to: $OUTPUT_DIR/performance-baselines.json${NC}"
}

# Main execution logic
case "$COMMAND" in
    "report")
        generate_performance_report
        ;;
    "monitor")
        continuous_monitoring
        ;;
    "capacity")
        capacity_planning
        ;;
    "optimize")
        performance_optimization
        ;;
    "baseline")
        establish_baselines
        ;;
    *)
        echo -e "${RED}❌ Unknown command: $COMMAND${NC}"
        show_usage
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}🎉 Performance monitoring completed${NC}"
echo -e "${BLUE}📁 Reports saved to: $REPORT_DIR${NC}"