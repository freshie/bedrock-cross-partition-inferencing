"""
Comprehensive error handling system for dual routing architecture
Provides standardized error responses, logging, and monitoring
"""

import json
import logging
import time
import traceback
from datetime import datetime
from enum import Enum
from typing import Dict, Any, Optional, Tuple
import boto3

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

class ErrorCategory(Enum):
    """Error categories for classification and handling"""
    AUTHENTICATION = "authentication"
    AUTHORIZATION = "authorization"
    VALIDATION = "validation"
    NETWORK = "network"
    SERVICE = "service"
    RATE_LIMITING = "rate_limiting"
    CONFIGURATION = "configuration"
    INTERNAL = "internal"
    VPN_SPECIFIC = "vpn_specific"
    INTERNET_SPECIFIC = "internet_specific"

class ErrorSeverity(Enum):
    """Error severity levels"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class DualRoutingError(Exception):
    """Base exception class for dual routing errors"""
    
    def __init__(self, 
                 message: str,
                 error_code: str,
                 category: ErrorCategory,
                 severity: ErrorSeverity = ErrorSeverity.MEDIUM,
                 routing_method: str = "unknown",
                 details: Dict[str, Any] = None,
                 http_status: int = 500,
                 retryable: bool = False):
        super().__init__(message)
        self.message = message
        self.error_code = error_code
        self.category = category
        self.severity = severity
        self.routing_method = routing_method
        self.details = details or {}
        self.http_status = http_status
        self.retryable = retryable
        self.timestamp = datetime.utcnow().isoformat() + 'Z'

class ErrorHandler:
    """Centralized error handling for dual routing"""
    
    def __init__(self, routing_method: str = "unknown"):
        self.routing_method = routing_method
        self.cloudwatch = boto3.client('cloudwatch')
        
    def handle_error(self, 
                    error: Exception, 
                    request_id: str,
                    context: Dict[str, Any] = None) -> Dict[str, Any]:
        """
        Handle any error and return standardized API Gateway response
        """
        context = context or {}
        
        # Convert to DualRoutingError if not already
        if not isinstance(error, DualRoutingError):
            dual_error = self._convert_to_dual_routing_error(error)
        else:
            dual_error = error
            
        # Log the error
        self._log_error(dual_error, request_id, context)
        
        # Send metrics
        self._send_error_metrics(dual_error, request_id)
        
        # Generate API Gateway response
        return self._generate_api_response(dual_error, request_id, context)
    
    def _convert_to_dual_routing_error(self, error: Exception) -> DualRoutingError:
        """Convert generic exceptions to DualRoutingError"""
        error_str = str(error).lower()
        
        # Authentication errors
        if any(keyword in error_str for keyword in ['unauthorized', 'authentication', 'invalid token', 'api key']):
            return DualRoutingError(
                message="Authentication failed",
                error_code="AUTHENTICATION_FAILED",
                category=ErrorCategory.AUTHENTICATION,
                severity=ErrorSeverity.MEDIUM,
                routing_method=self.routing_method,
                http_status=401,
                details={"original_error": str(error)}
            )
        
        # Authorization errors
        if any(keyword in error_str for keyword in ['forbidden', 'access denied', 'permission']):
            return DualRoutingError(
                message="Access denied",
                error_code="ACCESS_DENIED",
                category=ErrorCategory.AUTHORIZATION,
                severity=ErrorSeverity.MEDIUM,
                routing_method=self.routing_method,
                http_status=403,
                details={"original_error": str(error)}
            )
        
        # Validation errors
        if any(keyword in error_str for keyword in ['invalid', 'missing', 'required', 'validation']):
            return DualRoutingError(
                message="Request validation failed",
                error_code="VALIDATION_ERROR",
                category=ErrorCategory.VALIDATION,
                severity=ErrorSeverity.LOW,
                routing_method=self.routing_method,
                http_status=400,
                details={"original_error": str(error)}
            )
        
        # Network errors
        if any(keyword in error_str for keyword in ['timeout', 'connection', 'network', 'dns']):
            return DualRoutingError(
                message="Network error occurred",
                error_code="NETWORK_ERROR",
                category=ErrorCategory.NETWORK,
                severity=ErrorSeverity.HIGH,
                routing_method=self.routing_method,
                http_status=502,
                retryable=True,
                details={"original_error": str(error)}
            )
        
        # VPN-specific errors
        if any(keyword in error_str for keyword in ['vpn', 'tunnel', 'vpc endpoint']):
            return DualRoutingError(
                message="VPN connectivity error",
                error_code="VPN_ERROR",
                category=ErrorCategory.VPN_SPECIFIC,
                severity=ErrorSeverity.HIGH,
                routing_method=self.routing_method,
                http_status=503,
                retryable=True,
                details={"original_error": str(error)}
            )
        
        # Rate limiting errors
        if any(keyword in error_str for keyword in ['throttl', 'rate limit', '429']):
            return DualRoutingError(
                message="Request rate limit exceeded",
                error_code="RATE_LIMIT_EXCEEDED",
                category=ErrorCategory.RATE_LIMITING,
                severity=ErrorSeverity.MEDIUM,
                routing_method=self.routing_method,
                http_status=429,
                retryable=True,
                details={"original_error": str(error)}
            )
        
        # Service errors (Bedrock, AWS services)
        if any(keyword in error_str for keyword in ['bedrock', 'service', 'aws']):
            return DualRoutingError(
                message="External service error",
                error_code="SERVICE_ERROR",
                category=ErrorCategory.SERVICE,
                severity=ErrorSeverity.HIGH,
                routing_method=self.routing_method,
                http_status=502,
                retryable=True,
                details={"original_error": str(error)}
            )
        
        # Default internal error
        return DualRoutingError(
            message="Internal server error",
            error_code="INTERNAL_ERROR",
            category=ErrorCategory.INTERNAL,
            severity=ErrorSeverity.HIGH,
            routing_method=self.routing_method,
            http_status=500,
            details={"original_error": str(error)}
        )
    
    def _log_error(self, error: DualRoutingError, request_id: str, context: Dict[str, Any]):
        """Log error with appropriate level and context"""
        log_data = {
            "request_id": request_id,
            "error_code": error.error_code,
            "category": error.category.value,
            "severity": error.severity.value,
            "routing_method": error.routing_method,
            "message": error.message,
            "http_status": error.http_status,
            "retryable": error.retryable,
            "timestamp": error.timestamp,
            "details": error.details,
            "context": context
        }
        
        # Log with appropriate level based on severity
        if error.severity == ErrorSeverity.CRITICAL:
            logger.critical(f"CRITICAL ERROR: {json.dumps(log_data)}")
        elif error.severity == ErrorSeverity.HIGH:
            logger.error(f"HIGH SEVERITY ERROR: {json.dumps(log_data)}")
        elif error.severity == ErrorSeverity.MEDIUM:
            logger.warning(f"MEDIUM SEVERITY ERROR: {json.dumps(log_data)}")
        else:
            logger.info(f"LOW SEVERITY ERROR: {json.dumps(log_data)}")
        
        # Log stack trace for internal errors
        if error.category == ErrorCategory.INTERNAL:
            logger.error(f"Stack trace for request {request_id}: {traceback.format_exc()}")
    
    def _send_error_metrics(self, error: DualRoutingError, request_id: str):
        """Send error metrics to CloudWatch"""
        try:
            metrics = [
                {
                    'MetricName': 'ErrorCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'RoutingMethod', 'Value': error.routing_method},
                        {'Name': 'ErrorCategory', 'Value': error.category.value},
                        {'Name': 'ErrorCode', 'Value': error.error_code},
                        {'Name': 'Severity', 'Value': error.severity.value}
                    ]
                },
                {
                    'MetricName': 'ErrorsByHttpStatus',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'RoutingMethod', 'Value': error.routing_method},
                        {'Name': 'HttpStatus', 'Value': str(error.http_status)}
                    ]
                }
            ]
            
            # Add retryable error metric
            if error.retryable:
                metrics.append({
                    'MetricName': 'RetryableErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'RoutingMethod', 'Value': error.routing_method},
                        {'Name': 'ErrorCategory', 'Value': error.category.value}
                    ]
                })
            
            self.cloudwatch.put_metric_data(
                Namespace='CrossPartition/DualRouting/Errors',
                MetricData=[{
                    'MetricName': metric['MetricName'],
                    'Value': metric['Value'],
                    'Unit': metric['Unit'],
                    'Dimensions': metric['Dimensions'],
                    'Timestamp': datetime.utcnow()
                } for metric in metrics]
            )
            
        except Exception as e:
            logger.error(f"Failed to send error metrics: {str(e)}")
    
    def _generate_api_response(self, 
                              error: DualRoutingError, 
                              request_id: str, 
                              context: Dict[str, Any]) -> Dict[str, Any]:
        """Generate standardized API Gateway response"""
        
        # Base error response
        error_response = {
            "error": {
                "code": error.error_code,
                "message": error.message,
                "category": error.category.value,
                "routing_method": error.routing_method,
                "request_id": request_id,
                "timestamp": error.timestamp,
                "retryable": error.retryable
            }
        }
        
        # Add details for non-production or high severity errors
        if error.severity in [ErrorSeverity.HIGH, ErrorSeverity.CRITICAL] or context.get('include_details', False):
            error_response["error"]["details"] = error.details
        
        # Add troubleshooting information
        error_response["error"]["troubleshooting"] = self._get_troubleshooting_info(error)
        
        # Add retry information for retryable errors
        if error.retryable:
            error_response["error"]["retry"] = {
                "recommended_delay_seconds": self._get_retry_delay(error),
                "max_retries": self._get_max_retries(error)
            }
        
        return {
            'statusCode': error.http_status,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': request_id,
                'X-Error-Code': error.error_code,
                'X-Error-Category': error.category.value,
                'X-Routing-Method': error.routing_method,
                'X-Error-Retryable': str(error.retryable).lower()
            },
            'body': json.dumps(error_response)
        }
    
    def _get_troubleshooting_info(self, error: DualRoutingError) -> Dict[str, Any]:
        """Get troubleshooting information based on error type"""
        
        troubleshooting_guides = {
            ErrorCategory.AUTHENTICATION: {
                "description": "Authentication failed - check your API key or credentials",
                "common_causes": [
                    "Invalid or expired API key",
                    "Missing X-API-Key header",
                    "Incorrect authentication method"
                ],
                "solutions": [
                    "Verify your API key is correct and active",
                    "Check that you're using the correct authentication header",
                    "Ensure your API key has the right permissions"
                ]
            },
            ErrorCategory.AUTHORIZATION: {
                "description": "Access denied - insufficient permissions",
                "common_causes": [
                    "API key lacks permission for this routing method",
                    "Cross-routing attempt (internet key on VPN endpoint)",
                    "Usage plan restrictions"
                ],
                "solutions": [
                    "Use the correct API key for your routing method",
                    "Check your usage plan permissions",
                    "Contact administrator for access"
                ]
            },
            ErrorCategory.VPN_SPECIFIC: {
                "description": "VPN connectivity issue",
                "common_causes": [
                    "VPN tunnel is down",
                    "VPC endpoint unavailable",
                    "Network routing issues"
                ],
                "solutions": [
                    "Check VPN tunnel status",
                    "Verify VPC endpoint health",
                    "Try internet routing as fallback",
                    "Contact network administrator"
                ]
            },
            ErrorCategory.NETWORK: {
                "description": "Network connectivity problem",
                "common_causes": [
                    "DNS resolution failure",
                    "Connection timeout",
                    "Network congestion"
                ],
                "solutions": [
                    "Retry the request",
                    "Check network connectivity",
                    "Verify DNS settings"
                ]
            },
            ErrorCategory.RATE_LIMITING: {
                "description": "Request rate limit exceeded",
                "common_causes": [
                    "Too many requests in short time",
                    "Usage plan limits reached",
                    "Burst limit exceeded"
                ],
                "solutions": [
                    "Implement exponential backoff",
                    "Reduce request frequency",
                    "Consider upgrading usage plan"
                ]
            },
            ErrorCategory.SERVICE: {
                "description": "External service error",
                "common_causes": [
                    "Bedrock service unavailable",
                    "Model not available",
                    "Service maintenance"
                ],
                "solutions": [
                    "Retry with exponential backoff",
                    "Try different model if applicable",
                    "Check AWS service status"
                ]
            }
        }
        
        return troubleshooting_guides.get(error.category, {
            "description": "An error occurred",
            "solutions": ["Retry the request", "Contact support if problem persists"]
        })
    
    def _get_retry_delay(self, error: DualRoutingError) -> int:
        """Get recommended retry delay in seconds"""
        delay_map = {
            ErrorCategory.RATE_LIMITING: 60,
            ErrorCategory.NETWORK: 5,
            ErrorCategory.VPN_SPECIFIC: 10,
            ErrorCategory.SERVICE: 30
        }
        return delay_map.get(error.category, 5)
    
    def _get_max_retries(self, error: DualRoutingError) -> int:
        """Get maximum recommended retries"""
        retry_map = {
            ErrorCategory.RATE_LIMITING: 3,
            ErrorCategory.NETWORK: 3,
            ErrorCategory.VPN_SPECIFIC: 2,
            ErrorCategory.SERVICE: 3
        }
        return retry_map.get(error.category, 2)

# Predefined error classes for common scenarios
class AuthenticationError(DualRoutingError):
    def __init__(self, message: str = "Authentication failed", routing_method: str = "unknown", details: Dict[str, Any] = None):
        super().__init__(
            message=message,
            error_code="AUTHENTICATION_FAILED",
            category=ErrorCategory.AUTHENTICATION,
            severity=ErrorSeverity.MEDIUM,
            routing_method=routing_method,
            http_status=401,
            details=details
        )

class AuthorizationError(DualRoutingError):
    def __init__(self, message: str = "Access denied", routing_method: str = "unknown", details: Dict[str, Any] = None):
        super().__init__(
            message=message,
            error_code="ACCESS_DENIED",
            category=ErrorCategory.AUTHORIZATION,
            severity=ErrorSeverity.MEDIUM,
            routing_method=routing_method,
            http_status=403,
            details=details
        )

class ValidationError(DualRoutingError):
    def __init__(self, message: str = "Request validation failed", routing_method: str = "unknown", details: Dict[str, Any] = None):
        super().__init__(
            message=message,
            error_code="VALIDATION_ERROR",
            category=ErrorCategory.VALIDATION,
            severity=ErrorSeverity.LOW,
            routing_method=routing_method,
            http_status=400,
            details=details
        )

class VPNError(DualRoutingError):
    def __init__(self, message: str = "VPN connectivity error", routing_method: str = "vpn", details: Dict[str, Any] = None):
        super().__init__(
            message=message,
            error_code="VPN_ERROR",
            category=ErrorCategory.VPN_SPECIFIC,
            severity=ErrorSeverity.HIGH,
            routing_method=routing_method,
            http_status=503,
            retryable=True,
            details=details
        )

class NetworkError(DualRoutingError):
    def __init__(self, message: str = "Network error occurred", routing_method: str = "unknown", details: Dict[str, Any] = None):
        super().__init__(
            message=message,
            error_code="NETWORK_ERROR",
            category=ErrorCategory.NETWORK,
            severity=ErrorSeverity.HIGH,
            routing_method=routing_method,
            http_status=502,
            retryable=True,
            details=details
        )

class RateLimitError(DualRoutingError):
    def __init__(self, message: str = "Rate limit exceeded", routing_method: str = "unknown", details: Dict[str, Any] = None):
        super().__init__(
            message=message,
            error_code="RATE_LIMIT_EXCEEDED",
            category=ErrorCategory.RATE_LIMITING,
            severity=ErrorSeverity.MEDIUM,
            routing_method=routing_method,
            http_status=429,
            retryable=True,
            details=details
        )

class ServiceError(DualRoutingError):
    def __init__(self, message: str = "External service error", routing_method: str = "unknown", details: Dict[str, Any] = None):
        super().__init__(
            message=message,
            error_code="SERVICE_ERROR",
            category=ErrorCategory.SERVICE,
            severity=ErrorSeverity.HIGH,
            routing_method=routing_method,
            http_status=502,
            retryable=True,
            details=details
        )

# Utility functions for error handling
def create_error_handler(routing_method: str) -> ErrorHandler:
    """Create error handler for specific routing method"""
    return ErrorHandler(routing_method)

def handle_lambda_error(error: Exception, request_id: str, routing_method: str, context: Dict[str, Any] = None) -> Dict[str, Any]:
    """Quick error handling for Lambda functions"""
    handler = ErrorHandler(routing_method)
    return handler.handle_error(error, request_id, context)

def validate_request(event: Dict[str, Any], required_fields: list, routing_method: str) -> None:
    """Validate request and raise ValidationError if invalid"""
    missing_fields = []
    
    # Check for required fields in body
    body = event.get('body', {})
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except json.JSONDecodeError:
            raise ValidationError(
                message="Invalid JSON in request body",
                routing_method=routing_method,
                details={"body": event.get('body', '')}
            )
    
    for field in required_fields:
        if field not in body:
            missing_fields.append(field)
    
    if missing_fields:
        raise ValidationError(
            message=f"Missing required fields: {', '.join(missing_fields)}",
            routing_method=routing_method,
            details={"missing_fields": missing_fields, "received_fields": list(body.keys())}
        )