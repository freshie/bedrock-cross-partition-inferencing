"""
VPN-specific error handling module for cross-partition inference

This module provides specialized error handling for VPN tunnel failures,
VPC endpoint connectivity issues, and cross-partition routing failures.
"""

import logging
import time
import json
from datetime import datetime, timedelta
from typing import Dict, Any, Optional, List
from enum import Enum
from dataclasses import dataclass
import boto3
from botocore.exceptions import ClientError, EndpointConnectionError, ConnectTimeoutError

logger = logging.getLogger(__name__)

class ErrorSeverity(Enum):
    """Error severity levels"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class ErrorCategory(Enum):
    """Error categories for classification"""
    VPN_TUNNEL = "vpn_tunnel"
    VPC_ENDPOINT = "vpc_endpoint"
    ROUTING = "routing"
    AUTHENTICATION = "authentication"
    BEDROCK_API = "bedrock_api"
    NETWORK = "network"
    CONFIGURATION = "configuration"

@dataclass
class ErrorContext:
    """Context information for error handling"""
    request_id: str
    timestamp: datetime
    function_name: str
    routing_method: str
    vpc_endpoints_used: bool
    retry_attempt: int = 0
    max_retries: int = 3

class VPNTunnelError(Exception):
    """Exception for VPN tunnel failures"""
    
    def __init__(self, tunnel_id: str, status: str, message: str = None):
        self.tunnel_id = tunnel_id
        self.status = status
        self.severity = ErrorSeverity.CRITICAL
        self.category = ErrorCategory.VPN_TUNNEL
        super().__init__(message or f"VPN Tunnel {tunnel_id} failed: {status}")

class VPCEndpointError(Exception):
    """Exception for VPC endpoint connectivity issues"""
    
    def __init__(self, service: str, endpoint_id: str, message: str = None):
        self.service = service
        self.endpoint_id = endpoint_id
        self.severity = ErrorSeverity.HIGH
        self.category = ErrorCategory.VPC_ENDPOINT
        super().__init__(message or f"VPC Endpoint {endpoint_id} for {service} unavailable")

class CrossPartitionRoutingError(Exception):
    """Exception for cross-partition routing failures"""
    
    def __init__(self, destination_cidr: str, message: str = None):
        self.destination_cidr = destination_cidr
        self.severity = ErrorSeverity.CRITICAL
        self.category = ErrorCategory.ROUTING
        super().__init__(message or f"Routing failure to {destination_cidr}")

class BedrockAuthError(Exception):
    """Exception for Bedrock authentication failures"""
    
    def __init__(self, message: str = None):
        self.severity = ErrorSeverity.HIGH
        self.category = ErrorCategory.AUTHENTICATION
        super().__init__(message or "Bedrock authentication failed")

class CircuitBreakerError(Exception):
    """Exception when circuit breaker is open"""
    
    def __init__(self, service: str, message: str = None):
        self.service = service
        self.severity = ErrorSeverity.MEDIUM
        self.category = ErrorCategory.VPC_ENDPOINT
        super().__init__(message or f"Circuit breaker open for {service}")

class CircuitBreaker:
    """Circuit breaker implementation for VPC endpoint failures"""
    
    def __init__(self, failure_threshold: int = 5, recovery_timeout: int = 60):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.failure_count = {}
        self.last_failure_time = {}
        self.circuit_state = {}  # 'closed', 'open', 'half-open'
    
    def is_open(self, service_name: str) -> bool:
        """Check if circuit breaker is open for a service"""
        state = self.circuit_state.get(service_name, 'closed')
        
        if state == 'open':
            # Check if recovery timeout has passed
            last_failure = self.last_failure_time.get(service_name, 0)
            if time.time() - last_failure > self.recovery_timeout:
                self.circuit_state[service_name] = 'half-open'
                logger.info(f"Circuit breaker for {service_name} moved to half-open state")
                return False
            return True
        
        return False
    
    def record_success(self, service_name: str):
        """Record successful operation"""
        self.failure_count[service_name] = 0
        self.circuit_state[service_name] = 'closed'
        logger.debug(f"Circuit breaker for {service_name} reset to closed state")
    
    def record_failure(self, service_name: str):
        """Record failed operation"""
        self.failure_count[service_name] = self.failure_count.get(service_name, 0) + 1
        self.last_failure_time[service_name] = time.time()
        
        if self.failure_count[service_name] >= self.failure_threshold:
            self.circuit_state[service_name] = 'open'
            logger.warning(f"Circuit breaker for {service_name} opened after {self.failure_count[service_name]} failures")

# Global circuit breaker instance
circuit_breaker = CircuitBreaker()

class VPNErrorHandler:
    """Main error handler for VPN-related errors"""
    
    def __init__(self, cloudwatch_client=None):
        self.cloudwatch_client = cloudwatch_client or boto3.client('cloudwatch')
        self.error_metrics = []
    
    def handle_vpn_tunnel_failure(self, tunnel_status: Dict[str, Any], context: ErrorContext) -> Dict[str, Any]:
        """Handle VPN tunnel failure scenarios"""
        try:
            tunnel_id = tunnel_status.get('tunnel_id', 'unknown')
            status = tunnel_status.get('status', 'UNKNOWN')
            
            logger.error(f"VPN tunnel failure detected: {tunnel_id} status={status}")
            
            if status == "DOWN":
                # Attempt failover to backup tunnel
                failover_result = self._attempt_tunnel_failover(tunnel_status, context)
                
                # Record error metrics
                self._record_error_metric('VPNTunnelDown', tunnel_id, context)
                
                if failover_result['success']:
                    logger.info(f"Successfully failed over from tunnel {tunnel_id}")
                    return {
                        'action': 'failover_successful',
                        'backup_tunnel': failover_result['backup_tunnel'],
                        'message': f'Failed over to backup tunnel {failover_result["backup_tunnel"]}'
                    }
                else:
                    # Both tunnels down - critical error
                    raise VPNTunnelError(tunnel_id, status, "All VPN tunnels are down")
            
            elif status == "DEGRADED":
                # Log warning and continue with reduced performance
                logger.warning(f"VPN tunnel {tunnel_id} performance degraded")
                self._record_error_metric('VPNTunnelDegraded', tunnel_id, context)
                
                return {
                    'action': 'continue_with_monitoring',
                    'message': f'VPN tunnel {tunnel_id} degraded, monitoring performance'
                }
            
            else:
                # Unknown status
                logger.error(f"Unknown VPN tunnel status: {status}")
                return {
                    'action': 'monitor',
                    'message': f'Unknown tunnel status {status}, monitoring'
                }
        
        except Exception as e:
            logger.error(f"Error handling VPN tunnel failure: {str(e)}")
            raise VPNTunnelError(tunnel_id, status, f"Failed to handle tunnel failure: {str(e)}")
    
    def handle_vpc_endpoint_failure(self, service_name: str, endpoint_id: str, error: Exception, context: ErrorContext) -> Dict[str, Any]:
        """Handle VPC endpoint connectivity issues"""
        try:
            logger.error(f"VPC endpoint failure for {service_name}: {str(error)}")
            
            # Check circuit breaker
            if circuit_breaker.is_open(service_name):
                raise CircuitBreakerError(service_name, f"Circuit breaker open for {service_name}")
            
            # Record failure in circuit breaker
            circuit_breaker.record_failure(service_name)
            
            # Record error metrics
            self._record_error_metric('VPCEndpointFailure', service_name, context)
            
            # Attempt retry with exponential backoff
            if context.retry_attempt < context.max_retries:
                retry_delay = self._calculate_retry_delay(context.retry_attempt)
                
                logger.info(f"Retrying {service_name} VPC endpoint call in {retry_delay}s (attempt {context.retry_attempt + 1})")
                
                return {
                    'action': 'retry',
                    'retry_delay': retry_delay,
                    'retry_attempt': context.retry_attempt + 1,
                    'message': f'Retrying VPC endpoint call for {service_name}'
                }
            else:
                # Max retries exceeded
                raise VPCEndpointError(service_name, endpoint_id, f"Max retries exceeded for {service_name}")
        
        except CircuitBreakerError:
            raise
        except Exception as e:
            logger.error(f"Error handling VPC endpoint failure: {str(e)}")
            raise VPCEndpointError(service_name, endpoint_id, f"Failed to handle endpoint failure: {str(e)}")
    
    def handle_routing_failure(self, destination_cidr: str, context: ErrorContext) -> Dict[str, Any]:
        """Handle cross-partition routing failures"""
        try:
            logger.error(f"Routing failure to {destination_cidr}")
            
            # Check route table configuration
            route_check = self._check_route_table_entries(destination_cidr)
            
            if not route_check['route_exists']:
                logger.error(f"No route to {destination_cidr}")
                self._record_error_metric('RoutingNoRoute', destination_cidr, context)
                raise CrossPartitionRoutingError(destination_cidr, f"No route to {destination_cidr}")
            
            # Verify VPN Gateway status
            vpn_status = self._check_vpn_gateway_status()
            
            if vpn_status['status'] != 'available':
                logger.error(f"VPN Gateway status: {vpn_status['status']}")
                self._record_error_metric('VPNGatewayUnavailable', vpn_status['gateway_id'], context)
                raise CrossPartitionRoutingError(destination_cidr, f"VPN Gateway unavailable: {vpn_status['status']}")
            
            # If route exists and VPN is available, might be temporary network issue
            return {
                'action': 'retry_with_delay',
                'retry_delay': 5,
                'message': f'Temporary routing issue to {destination_cidr}, retrying'
            }
        
        except CrossPartitionRoutingError:
            raise
        except Exception as e:
            logger.error(f"Error handling routing failure: {str(e)}")
            raise CrossPartitionRoutingError(destination_cidr, f"Failed to handle routing failure: {str(e)}")
    
    def handle_bedrock_auth_failure(self, context: ErrorContext) -> Dict[str, Any]:
        """Handle Bedrock API key authentication failures"""
        try:
            logger.error("Bedrock authentication failure")
            
            # Try to retrieve fresh API key from Secrets Manager via VPC endpoint
            try:
                if context.vpc_endpoints_used:
                    # Use VPC endpoint for Secrets Manager
                    secrets_client = boto3.client('secretsmanager', 
                                                endpoint_url=context.vpc_endpoint_secrets)
                else:
                    secrets_client = boto3.client('secretsmanager')
                
                secret = secrets_client.get_secret_value(
                    SecretId='cross-partition-commercial-creds'
                )
                credentials = json.loads(secret['SecretString'])
                
                if 'bedrock_api_key' in credentials:
                    logger.info("Successfully retrieved fresh Bedrock API key")
                    circuit_breaker.record_success('secretsmanager')
                    
                    return {
                        'action': 'retry_with_fresh_credentials',
                        'credentials': credentials,
                        'message': 'Retrieved fresh Bedrock API key'
                    }
                else:
                    raise BedrockAuthError("No Bedrock API key in credentials")
            
            except Exception as e:
                logger.error(f"Failed to retrieve fresh Bedrock API key: {str(e)}")
                circuit_breaker.record_failure('secretsmanager')
                self._record_error_metric('BedrockAuthFailure', 'api_key_retrieval', context)
                raise BedrockAuthError(f"Unable to authenticate with Bedrock service: {str(e)}")
        
        except BedrockAuthError:
            raise
        except Exception as e:
            logger.error(f"Error handling Bedrock auth failure: {str(e)}")
            raise BedrockAuthError(f"Failed to handle auth failure: {str(e)}")
    
    def _attempt_tunnel_failover(self, tunnel_status: Dict[str, Any], context: ErrorContext) -> Dict[str, Any]:
        """Attempt to failover to backup VPN tunnel"""
        try:
            # In a real implementation, this would check VPN connection status
            # and attempt to route traffic through the backup tunnel
            
            # Simulate checking backup tunnel status
            backup_tunnel_id = f"tunnel-backup-{tunnel_status.get('tunnel_id', 'unknown')}"
            
            # For demo purposes, assume backup tunnel is available
            # In production, this would query AWS EC2 API for actual tunnel status
            
            logger.info(f"Attempting failover to backup tunnel {backup_tunnel_id}")
            
            return {
                'success': True,
                'backup_tunnel': backup_tunnel_id,
                'message': f'Successfully failed over to {backup_tunnel_id}'
            }
        
        except Exception as e:
            logger.error(f"Failover attempt failed: {str(e)}")
            return {
                'success': False,
                'error': str(e),
                'message': 'Failover attempt failed'
            }
    
    def _check_route_table_entries(self, destination_cidr: str) -> Dict[str, Any]:
        """Check if route exists in route tables"""
        try:
            # In a real implementation, this would check actual route tables
            # For demo purposes, assume route exists for known CIDRs
            
            known_cidrs = ['172.16.0.0/16', '10.0.0.0/16']
            route_exists = destination_cidr in known_cidrs
            
            return {
                'route_exists': route_exists,
                'destination_cidr': destination_cidr,
                'message': f'Route {"exists" if route_exists else "not found"} for {destination_cidr}'
            }
        
        except Exception as e:
            logger.error(f"Error checking route tables: {str(e)}")
            return {
                'route_exists': False,
                'error': str(e),
                'message': f'Failed to check routes for {destination_cidr}'
            }
    
    def _check_vpn_gateway_status(self) -> Dict[str, Any]:
        """Check VPN Gateway status"""
        try:
            # In a real implementation, this would query EC2 API for VPN Gateway status
            # For demo purposes, assume VPN Gateway is available
            
            return {
                'status': 'available',
                'gateway_id': 'vgw-demo123',
                'message': 'VPN Gateway is available'
            }
        
        except Exception as e:
            logger.error(f"Error checking VPN Gateway status: {str(e)}")
            return {
                'status': 'unknown',
                'error': str(e),
                'message': f'Failed to check VPN Gateway status: {str(e)}'
            }
    
    def _calculate_retry_delay(self, attempt: int) -> float:
        """Calculate exponential backoff delay"""
        base_delay = 0.1
        max_delay = 30.0
        delay = min(base_delay * (2 ** attempt), max_delay)
        return delay
    
    def _record_error_metric(self, metric_name: str, resource_id: str, context: ErrorContext):
        """Record error metric to CloudWatch"""
        try:
            metric_data = {
                'MetricName': metric_name,
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'ResourceId', 'Value': resource_id},
                    {'Name': 'RoutingMethod', 'Value': context.routing_method},
                    {'Name': 'FunctionName', 'Value': context.function_name}
                ],
                'Timestamp': context.timestamp
            }
            
            self.error_metrics.append(metric_data)
            
            # Send metrics in batches to avoid API limits
            if len(self.error_metrics) >= 20:
                self._flush_error_metrics()
        
        except Exception as e:
            logger.error(f"Failed to record error metric: {str(e)}")
    
    def _flush_error_metrics(self):
        """Flush accumulated error metrics to CloudWatch"""
        try:
            if self.error_metrics:
                self.cloudwatch_client.put_metric_data(
                    Namespace='CrossPartition/VPN/Errors',
                    MetricData=self.error_metrics
                )
                
                logger.info(f"Sent {len(self.error_metrics)} error metrics to CloudWatch")
                self.error_metrics.clear()
        
        except Exception as e:
            logger.error(f"Failed to flush error metrics: {str(e)}")
    
    def get_error_summary(self) -> Dict[str, Any]:
        """Get summary of error handling state"""
        return {
            'circuit_breaker_states': circuit_breaker.circuit_state.copy(),
            'failure_counts': circuit_breaker.failure_count.copy(),
            'pending_metrics': len(self.error_metrics),
            'timestamp': datetime.utcnow().isoformat()
        }

def create_error_context(request_id: str, function_name: str, routing_method: str = 'vpn', 
                        vpc_endpoints_used: bool = True, retry_attempt: int = 0) -> ErrorContext:
    """Factory function to create error context"""
    return ErrorContext(
        request_id=request_id,
        timestamp=datetime.utcnow(),
        function_name=function_name,
        routing_method=routing_method,
        vpc_endpoints_used=vpc_endpoints_used,
        retry_attempt=retry_attempt
    )

def handle_exception_with_context(exception: Exception, context: ErrorContext, 
                                error_handler: VPNErrorHandler) -> Dict[str, Any]:
    """Handle exceptions with proper context and error classification"""
    try:
        if isinstance(exception, VPNTunnelError):
            return error_handler.handle_vpn_tunnel_failure(
                {'tunnel_id': exception.tunnel_id, 'status': exception.status}, 
                context
            )
        
        elif isinstance(exception, VPCEndpointError):
            return error_handler.handle_vpc_endpoint_failure(
                exception.service, exception.endpoint_id, exception, context
            )
        
        elif isinstance(exception, CrossPartitionRoutingError):
            return error_handler.handle_routing_failure(exception.destination_cidr, context)
        
        elif isinstance(exception, BedrockAuthError):
            return error_handler.handle_bedrock_auth_failure(context)
        
        elif isinstance(exception, (EndpointConnectionError, ConnectTimeoutError)):
            # Network-level errors
            return error_handler.handle_vpc_endpoint_failure(
                'network', 'unknown', exception, context
            )
        
        else:
            # Generic error handling
            logger.error(f"Unhandled exception: {type(exception).__name__}: {str(exception)}")
            error_handler._record_error_metric('UnhandledException', type(exception).__name__, context)
            
            return {
                'action': 'log_and_fail',
                'error_type': type(exception).__name__,
                'message': str(exception)
            }
    
    except Exception as handler_error:
        logger.error(f"Error in exception handler: {str(handler_error)}")
        return {
            'action': 'critical_failure',
            'original_error': str(exception),
            'handler_error': str(handler_error),
            'message': 'Critical failure in error handling'
        }