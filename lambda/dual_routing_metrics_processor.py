"""
Dual Routing Metrics Processor
Processes and aggregates metrics from DynamoDB request logs and CloudWatch
Generates insights and custom alerts for dual routing system
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Dict, List, Any, Optional
from collections import defaultdict

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'cross-partition-dual-routing')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'prod')
REQUEST_LOG_TABLE = os.environ.get('REQUEST_LOG_TABLE', 'cross-partition-requests')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

# AWS clients
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

class MetricsProcessor:
    """Process and analyze dual routing metrics"""
    
    def __init__(self):
        self.table = dynamodb.Table(REQUEST_LOG_TABLE)
        self.metrics_namespace = 'CrossPartition/DualRouting/Analytics'
        
    def process_metrics(self, time_window_minutes: int = 5) -> Dict[str, Any]:
        """Process metrics for the specified time window"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=time_window_minutes)
        
        logger.info(f"Processing metrics from {start_time} to {end_time}")
        
        # Get request data from DynamoDB
        request_data = self._get_request_data(start_time, end_time)
        
        # Calculate metrics
        metrics = self._calculate_metrics(request_data)
        
        # Send custom metrics to CloudWatch
        self._send_custom_metrics(metrics)
        
        # Check for anomalies and send alerts
        self._check_anomalies(metrics)
        
        return metrics
    
    def _get_request_data(self, start_time: datetime, end_time: datetime) -> List[Dict[str, Any]]:
        """Retrieve request data from DynamoDB within time window"""
        try:
            # Convert to ISO format for DynamoDB query
            start_iso = start_time.isoformat() + 'Z'
            end_iso = end_time.isoformat() + 'Z'
            
            # Scan table for recent requests (in production, consider using GSI with timestamp)
            response = self.table.scan(
                FilterExpression='#ts BETWEEN :start_time AND :end_time',
                ExpressionAttributeNames={
                    '#ts': 'timestamp'
                },
                ExpressionAttributeValues={
                    ':start_time': start_iso,
                    ':end_time': end_iso
                }
            )
            
            return response.get('Items', [])
            
        except Exception as e:
            logger.error(f"Error retrieving request data: {str(e)}")
            return []
    
    def _calculate_metrics(self, request_data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate comprehensive metrics from request data"""
        metrics = {
            'total_requests': 0,
            'routing_methods': defaultdict(int),
            'success_rates': defaultdict(lambda: {'success': 0, 'total': 0}),
            'latency_stats': defaultdict(list),
            'error_categories': defaultdict(int),
            'model_usage': defaultdict(int),
            'user_activity': defaultdict(int),
            'vpc_endpoint_health': defaultdict(list),
            'request_sizes': defaultdict(list),
            'response_sizes': defaultdict(list)
        }
        
        for request in request_data:
            try:
                # Convert Decimal to appropriate types
                request = self._convert_decimals(request)
                
                routing_method = request.get('routingMethod', 'unknown')
                success = request.get('success', False)
                latency = request.get('latency', 0)
                model_id = request.get('modelId', 'unknown')
                user_arn = request.get('userArn', 'unknown')
                request_size = request.get('requestSize', 0)
                response_size = request.get('responseSize', 0)
                
                # Basic counts
                metrics['total_requests'] += 1
                metrics['routing_methods'][routing_method] += 1
                
                # Success rates
                metrics['success_rates'][routing_method]['total'] += 1
                if success:
                    metrics['success_rates'][routing_method]['success'] += 1
                
                # Latency statistics
                metrics['latency_stats'][routing_method].append(latency)
                
                # Error tracking
                if not success and 'errorMessage' in request:
                    error_msg = request['errorMessage'].lower()
                    if 'authentication' in error_msg:
                        metrics['error_categories']['authentication'] += 1
                    elif 'vpn' in error_msg or 'tunnel' in error_msg:
                        metrics['error_categories']['vpn_specific'] += 1
                    elif 'network' in error_msg or 'timeout' in error_msg:
                        metrics['error_categories']['network'] += 1
                    elif 'validation' in error_msg:
                        metrics['error_categories']['validation'] += 1
                    else:
                        metrics['error_categories']['other'] += 1
                
                # Model usage
                metrics['model_usage'][model_id] += 1
                
                # User activity
                metrics['user_activity'][user_arn] += 1
                
                # Request/Response sizes
                metrics['request_sizes'][routing_method].append(request_size)
                metrics['response_sizes'][routing_method].append(response_size)
                
            except Exception as e:
                logger.error(f"Error processing request data: {str(e)}")
                continue
        
        # Calculate derived metrics
        metrics['derived'] = self._calculate_derived_metrics(metrics)
        
        return metrics
    
    def _convert_decimals(self, obj):
        """Convert DynamoDB Decimal objects to appropriate Python types"""
        if isinstance(obj, dict):
            return {k: self._convert_decimals(v) for k, v in obj.items()}
        elif isinstance(obj, list):
            return [self._convert_decimals(v) for v in obj]
        elif isinstance(obj, Decimal):
            return float(obj) if obj % 1 else int(obj)
        else:
            return obj
    
    def _calculate_derived_metrics(self, metrics: Dict[str, Any]) -> Dict[str, Any]:
        """Calculate derived metrics and insights"""
        derived = {}
        
        # Success rate percentages
        derived['success_rate_percentages'] = {}
        for routing_method, stats in metrics['success_rates'].items():
            if stats['total'] > 0:
                derived['success_rate_percentages'][routing_method] = (
                    stats['success'] / stats['total'] * 100
                )
        
        # Latency percentiles
        derived['latency_percentiles'] = {}
        for routing_method, latencies in metrics['latency_stats'].items():
            if latencies:
                sorted_latencies = sorted(latencies)
                n = len(sorted_latencies)
                derived['latency_percentiles'][routing_method] = {
                    'p50': sorted_latencies[int(n * 0.5)],
                    'p90': sorted_latencies[int(n * 0.9)],
                    'p95': sorted_latencies[int(n * 0.95)],
                    'p99': sorted_latencies[int(n * 0.99)] if n > 1 else sorted_latencies[0],
                    'avg': sum(latencies) / len(latencies),
                    'max': max(latencies),
                    'min': min(latencies)
                }
        
        # Traffic distribution
        total_requests = metrics['total_requests']
        if total_requests > 0:
            derived['traffic_distribution'] = {
                routing_method: (count / total_requests * 100)
                for routing_method, count in metrics['routing_methods'].items()
            }
        
        # Error rate percentages
        total_errors = sum(metrics['error_categories'].values())
        if total_errors > 0:
            derived['error_distribution'] = {
                category: (count / total_errors * 100)
                for category, count in metrics['error_categories'].items()
            }
        
        # Average request/response sizes
        derived['average_sizes'] = {}
        for routing_method in metrics['request_sizes']:
            req_sizes = metrics['request_sizes'][routing_method]
            resp_sizes = metrics['response_sizes'][routing_method]
            
            derived['average_sizes'][routing_method] = {
                'avg_request_size': sum(req_sizes) / len(req_sizes) if req_sizes else 0,
                'avg_response_size': sum(resp_sizes) / len(resp_sizes) if resp_sizes else 0
            }
        
        return derived
    
    def _send_custom_metrics(self, metrics: Dict[str, Any]):
        """Send custom metrics to CloudWatch"""
        try:
            metric_data = []
            
            # Success rate metrics
            for routing_method, percentage in metrics['derived'].get('success_rate_percentages', {}).items():
                metric_data.append({
                    'MetricName': 'SuccessRatePercentage',
                    'Value': percentage,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'RoutingMethod', 'Value': routing_method}
                    ]
                })
            
            # Latency percentile metrics
            for routing_method, percentiles in metrics['derived'].get('latency_percentiles', {}).items():
                for percentile, value in percentiles.items():
                    metric_data.append({
                        'MetricName': f'Latency{percentile.upper()}',
                        'Value': value,
                        'Unit': 'Milliseconds',
                        'Dimensions': [
                            {'Name': 'RoutingMethod', 'Value': routing_method}
                        ]
                    })
            
            # Traffic distribution metrics
            for routing_method, percentage in metrics['derived'].get('traffic_distribution', {}).items():
                metric_data.append({
                    'MetricName': 'TrafficDistribution',
                    'Value': percentage,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {'Name': 'RoutingMethod', 'Value': routing_method}
                    ]
                })
            
            # Error category metrics
            for category, count in metrics['error_categories'].items():
                metric_data.append({
                    'MetricName': 'ErrorsByCategory',
                    'Value': count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'ErrorCategory', 'Value': category}
                    ]
                })
            
            # Send metrics in batches (CloudWatch limit is 20 per call)
            for i in range(0, len(metric_data), 20):
                batch = metric_data[i:i+20]
                cloudwatch.put_metric_data(
                    Namespace=self.metrics_namespace,
                    MetricData=[{
                        **metric,
                        'Timestamp': datetime.utcnow()
                    } for metric in batch]
                )
            
            logger.info(f"Sent {len(metric_data)} custom metrics to CloudWatch")
            
        except Exception as e:
            logger.error(f"Error sending custom metrics: {str(e)}")
    
    def _check_anomalies(self, metrics: Dict[str, Any]):
        """Check for anomalies and send alerts"""
        alerts = []
        
        # Check success rates
        for routing_method, percentage in metrics['derived'].get('success_rate_percentages', {}).items():
            if percentage < 95:  # Less than 95% success rate
                alerts.append({
                    'severity': 'HIGH' if percentage < 90 else 'MEDIUM',
                    'title': f'Low Success Rate - {routing_method.title()} Routing',
                    'message': f'Success rate for {routing_method} routing is {percentage:.1f}%',
                    'routing_method': routing_method,
                    'metric': 'success_rate',
                    'value': percentage
                })
        
        # Check latency
        for routing_method, percentiles in metrics['derived'].get('latency_percentiles', {}).items():
            p95_latency = percentiles.get('p95', 0)
            if p95_latency > 30000:  # P95 latency > 30 seconds
                alerts.append({
                    'severity': 'HIGH' if p95_latency > 60000 else 'MEDIUM',
                    'title': f'High Latency - {routing_method.title()} Routing',
                    'message': f'P95 latency for {routing_method} routing is {p95_latency:.0f}ms',
                    'routing_method': routing_method,
                    'metric': 'latency_p95',
                    'value': p95_latency
                })
        
        # Check error patterns
        total_errors = sum(metrics['error_categories'].values())
        if total_errors > 0:
            # VPN-specific errors
            vpn_errors = metrics['error_categories'].get('vpn_specific', 0)
            if vpn_errors > 5:  # More than 5 VPN errors in time window
                alerts.append({
                    'severity': 'HIGH',
                    'title': 'VPN Connectivity Issues',
                    'message': f'{vpn_errors} VPN-related errors detected in the last 5 minutes',
                    'routing_method': 'vpn',
                    'metric': 'vpn_errors',
                    'value': vpn_errors
                })
            
            # Authentication errors
            auth_errors = metrics['error_categories'].get('authentication', 0)
            if auth_errors > 10:  # More than 10 auth errors
                alerts.append({
                    'severity': 'MEDIUM',
                    'title': 'High Authentication Failures',
                    'message': f'{auth_errors} authentication failures detected',
                    'routing_method': 'both',
                    'metric': 'auth_errors',
                    'value': auth_errors
                })
        
        # Send alerts
        for alert in alerts:
            self._send_alert(alert)
    
    def _send_alert(self, alert: Dict[str, Any]):
        """Send alert via SNS"""
        if not SNS_TOPIC_ARN:
            logger.warning("No SNS topic configured for alerts")
            return
        
        try:
            subject = f"[{alert['severity']}] {PROJECT_NAME} - {alert['title']}"
            
            message = f"""
Dual Routing Alert - {ENVIRONMENT.upper()} Environment

Alert: {alert['title']}
Severity: {alert['severity']}
Routing Method: {alert['routing_method']}
Metric: {alert['metric']}
Value: {alert['value']}

Description: {alert['message']}

Time: {datetime.utcnow().isoformat()}Z
Project: {PROJECT_NAME}
Environment: {ENVIRONMENT}

Please investigate and take appropriate action.
            """.strip()
            
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=subject,
                Message=message
            )
            
            logger.info(f"Sent {alert['severity']} alert: {alert['title']}")
            
        except Exception as e:
            logger.error(f"Error sending alert: {str(e)}")

def lambda_handler(event, context):
    """Lambda handler for metrics processing"""
    try:
        logger.info("Starting dual routing metrics processing")
        
        processor = MetricsProcessor()
        
        # Process metrics for the last 5 minutes
        metrics = processor.process_metrics(time_window_minutes=5)
        
        # Log summary
        logger.info(f"Processed {metrics['total_requests']} requests")
        logger.info(f"Routing distribution: {dict(metrics['routing_methods'])}")
        logger.info(f"Error categories: {dict(metrics['error_categories'])}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Metrics processed successfully',
                'total_requests': metrics['total_requests'],
                'routing_methods': dict(metrics['routing_methods']),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in metrics processing: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

# For local testing
if __name__ == '__main__':
    # Mock event and context for testing
    test_event = {}
    test_context = type('Context', (), {
        'aws_request_id': 'test-request-id',
        'function_name': 'test-metrics-processor'
    })()
    
    result = lambda_handler(test_event, test_context)
    print(json.dumps(result, indent=2))