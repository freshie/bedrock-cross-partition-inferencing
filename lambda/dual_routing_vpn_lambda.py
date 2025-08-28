import json
import boto3
import logging
import time
import uuid
import os
import urllib.request
import urllib.error
from datetime import datetime
from botocore.exceptions import ClientError, NoCredentialsError
from functools import lru_cache
from typing import Dict, Any, Optional

# Import error handling system
from dual_routing_error_handler import (
    ErrorHandler, DualRoutingError, VPNError, NetworkError, 
    AuthenticationError, ValidationError, ServiceError,
    validate_request, handle_lambda_error
)

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables for VPC endpoints
VPC_ENDPOINT_SECRETS = os.environ.get('VPC_ENDPOINT_SECRETS')
VPC_ENDPOINT_DYNAMODB = os.environ.get('VPC_ENDPOINT_DYNAMODB')
VPC_ENDPOINT_LOGS = os.environ.get('VPC_ENDPOINT_LOGS')
VPC_ENDPOINT_MONITORING = os.environ.get('VPC_ENDPOINT_MONITORING')
COMMERCIAL_BEDROCK_ENDPOINT = os.environ.get('COMMERCIAL_BEDROCK_ENDPOINT')

# Configuration
COMMERCIAL_CREDENTIALS_SECRET = os.environ.get('COMMERCIAL_CREDENTIALS_SECRET', 'cross-partition-commercial-creds')
REQUEST_LOG_TABLE = os.environ.get('REQUEST_LOG_TABLE', 'cross-partition-requests')
ROUTING_METHOD = 'vpn'

class VPCEndpointClients:
    """Singleton class for VPC endpoint clients to avoid recreation with health checks"""
    
    _instance = None
    _clients = {}
    _health_status = {}
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(VPCEndpointClients, cls).__new__(cls)
        return cls._instance
    
    def check_vpc_endpoint_health(self, endpoint_name, endpoint_url):
        """Check if VPC endpoint is healthy"""
        try:
            # Simple connectivity test - try to resolve the endpoint
            import socket
            from urllib.parse import urlparse
            
            if endpoint_url:
                parsed = urlparse(endpoint_url)
                host = parsed.hostname
                port = parsed.port or 443
                
                # Test connection with short timeout
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(2)
                result = sock.connect_ex((host, port))
                sock.close()
                
                is_healthy = result == 0
                self._health_status[endpoint_name] = {
                    'healthy': is_healthy,
                    'last_check': datetime.utcnow().isoformat(),
                    'endpoint_url': endpoint_url
                }
                
                if not is_healthy:
                    logger.warning(f"VPC endpoint {endpoint_name} health check failed: {endpoint_url}")
                
                return is_healthy
            else:
                # No endpoint configured, assume healthy (will use default AWS endpoints)
                self._health_status[endpoint_name] = {
                    'healthy': True,
                    'last_check': datetime.utcnow().isoformat(),
                    'endpoint_url': 'default'
                }
                return True
                
        except Exception as e:
            logger.error(f"VPC endpoint health check failed for {endpoint_name}: {str(e)}")
            self._health_status[endpoint_name] = {
                'healthy': False,
                'last_check': datetime.utcnow().isoformat(),
                'error': str(e)
            }
            return False
    
    @lru_cache(maxsize=1)
    def get_secrets_client(self):
        """Get Secrets Manager client configured for VPC endpoint with health check"""
        # Check endpoint health before creating client
        if VPC_ENDPOINT_SECRETS:
            is_healthy = self.check_vpc_endpoint_health('secrets', VPC_ENDPOINT_SECRETS)
            if not is_healthy:
                logger.warning("Secrets Manager VPC endpoint unhealthy, falling back to default")
                return boto3.client('secretsmanager')
            return boto3.client('secretsmanager', endpoint_url=VPC_ENDPOINT_SECRETS)
        return boto3.client('secretsmanager')
    
    @lru_cache(maxsize=1)
    def get_dynamodb_resource(self):
        """Get DynamoDB resource configured for VPC endpoint with health check"""
        if VPC_ENDPOINT_DYNAMODB:
            is_healthy = self.check_vpc_endpoint_health('dynamodb', VPC_ENDPOINT_DYNAMODB)
            if not is_healthy:
                logger.warning("DynamoDB VPC endpoint unhealthy, falling back to default")
                return boto3.resource('dynamodb')
            return boto3.resource('dynamodb', endpoint_url=VPC_ENDPOINT_DYNAMODB)
        return boto3.resource('dynamodb')
    
    @lru_cache(maxsize=1)
    def get_cloudwatch_client(self):
        """Get CloudWatch client configured for VPC endpoint with health check"""
        if VPC_ENDPOINT_MONITORING:
            is_healthy = self.check_vpc_endpoint_health('cloudwatch', VPC_ENDPOINT_MONITORING)
            if not is_healthy:
                logger.warning("CloudWatch VPC endpoint unhealthy, falling back to default")
                return boto3.client('cloudwatch')
            return boto3.client('cloudwatch', endpoint_url=VPC_ENDPOINT_MONITORING)
        return boto3.client('cloudwatch')
    
    def get_health_status(self):
        """Get health status of all VPC endpoints"""
        return self._health_status.copy()
    
    def validate_vpn_connectivity(self):
        """Validate VPN tunnel connectivity by testing commercial Bedrock endpoint"""
        try:
            if COMMERCIAL_BEDROCK_ENDPOINT:
                # Test connectivity to commercial Bedrock via VPN
                import socket
                from urllib.parse import urlparse
                
                parsed = urlparse(COMMERCIAL_BEDROCK_ENDPOINT)
                host = parsed.hostname
                port = parsed.port or 443
                
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(5)  # Longer timeout for VPN
                result = sock.connect_ex((host, port))
                sock.close()
                
                vpn_healthy = result == 0
                self._health_status['vpn_tunnel'] = {
                    'healthy': vpn_healthy,
                    'last_check': datetime.utcnow().isoformat(),
                    'endpoint': COMMERCIAL_BEDROCK_ENDPOINT
                }
                
                if not vpn_healthy:
                    logger.error(f"VPN tunnel connectivity test failed to {COMMERCIAL_BEDROCK_ENDPOINT}")
                    raise Exception("VPN tunnel appears to be down or unreachable")
                
                logger.info("VPN tunnel connectivity validated successfully")
                return True
            else:
                # No specific VPN endpoint configured, assume standard routing
                logger.info("No VPN endpoint configured, using standard AWS routing")
                return True
                
        except Exception as e:
            logger.error(f"VPN connectivity validation failed: {str(e)}")
            self._health_status['vpn_tunnel'] = {
                'healthy': False,
                'last_check': datetime.utcnow().isoformat(),
                'error': str(e)
            }
            raise Exception(f"VPN tunnel validation failed: {str(e)}")
        if VPC_ENDPOINT_DYNAMODB:
            return boto3.resource('dynamodb', endpoint_url=VPC_ENDPOINT_DYNAMODB)
        return boto3.resource('dynamodb')
    
    @lru_cache(maxsize=1)
    def get_cloudwatch_client(self):
        """Get CloudWatch client configured for VPC endpoint"""
        if VPC_ENDPOINT_MONITORING:
            return boto3.client('cloudwatch', endpoint_url=VPC_ENDPOINT_MONITORING)
        return boto3.client('cloudwatch')

# Global VPC clients instance
vpc_clients = VPCEndpointClients()

def lambda_handler(event, context):
    """
    Main Lambda handler for VPN-routed cross-partition Bedrock requests
    Enhanced with comprehensive error handling system
    """
    request_id = str(uuid.uuid4())
    start_time = time.time()
    error_handler = ErrorHandler(ROUTING_METHOD)
    
    try:
        # Log VPC configuration for debugging
        logger.info(f"Request {request_id}: VPN Lambda - VPC endpoint configuration - "
                    f"Secrets: {bool(VPC_ENDPOINT_SECRETS)}, "
                    f"DynamoDB: {bool(VPC_ENDPOINT_DYNAMODB)}, "
                    f"Routing: {ROUTING_METHOD}")
        
        # Detect routing method from API Gateway path
        path = event.get('path', '')
        detected_routing = detect_routing_method(path)
        logger.info(f"Request {request_id}: Detected routing method: {detected_routing} from path: {path}")
        
        # Validate this is a VPN request
        if detected_routing != 'vpn':
            raise ValidationError(
                message='This Lambda function only handles VPN routing requests',
                routing_method=ROUTING_METHOD,
                details={
                    'expected_path': '/v1/vpn/bedrock/invoke-model',
                    'received_path': path,
                    'detected_routing': detected_routing
                }
            )
        
        # Check if this is a GET request
        http_method = event.get('httpMethod', 'POST')
        
        if http_method == 'GET':
            if 'models' in path:
                return get_available_models(event, context)
            else:
                return get_routing_info(event, context)
        
        # Validate request format for POST requests
        validate_request(event, ['modelId'], ROUTING_METHOD)
        
        # Validate VPN connectivity before processing request
        logger.info(f"Request {request_id}: Validating VPN connectivity...")
        try:
            vpc_clients.validate_vpn_connectivity()
        except Exception as vpn_error:
            raise VPNError(
                message='VPN connectivity validation failed',
                routing_method=ROUTING_METHOD,
                details={'vpn_error': str(vpn_error)}
            )
        
        # Parse the incoming request
        request_data = parse_request(event)
        logger.info(f"Request {request_id}: Parsed request for model {request_data.get('modelId')}")
        
        # Get commercial Bedrock credentials via VPC endpoint with retry logic
        try:
            commercial_creds = get_commercial_credentials_vpc_with_retry(request_id)
            logger.info(f"Request {request_id}: Retrieved commercial credentials via VPC endpoint")
        except Exception as cred_error:
            raise AuthenticationError(
                message='Failed to retrieve commercial credentials',
                routing_method=ROUTING_METHOD,
                details={'credential_error': str(cred_error)}
            )
        
        # Forward request to commercial Bedrock via VPN with enhanced error handling
        try:
            response = forward_to_bedrock_vpn_enhanced(commercial_creds, request_data, request_id)
            logger.info(f"Request {request_id}: Successfully forwarded to commercial Bedrock via VPN")
        except Exception as bedrock_error:
            raise ServiceError(
                message='Failed to forward request to commercial Bedrock',
                routing_method=ROUTING_METHOD,
                details={'bedrock_error': str(bedrock_error)}
            )
        
        # Calculate latency
        latency = int((time.time() - start_time) * 1000)  # milliseconds
        
        # Log request to DynamoDB via VPC endpoint
        log_request_vpc(request_id, request_data, response, latency, True)
        
        # Send custom metrics via VPC endpoint
        send_custom_metrics(request_id, latency, True)
        
        # Get VPC endpoint health status for response metadata
        health_status = vpc_clients.get_health_status()
        
        # Return successful response with VPN routing metadata
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': request_id,
                'X-Source-Partition': 'govcloud',
                'X-Destination-Partition': 'commercial',
                'X-Routing-Method': ROUTING_METHOD,
                'X-VPC-Endpoints-Used': 'true',
                'X-VPN-Tunnel-Status': 'healthy'
            },
            'body': json.dumps({
                **response,
                'routing_method': ROUTING_METHOD,
                'vpc_endpoint_health': {k: v.get('healthy', False) for k, v in health_status.items()}
            })
        }
        
    except Exception as e:
        # Calculate latency for failed request
        latency = int((time.time() - start_time) * 1000)
        
        # Log failed request to DynamoDB via VPC endpoint
        try:
            request_data = parse_request(event) if 'request_data' not in locals() else request_data
            log_request_vpc(request_id, request_data, None, latency, False, str(e))
            send_custom_metrics(request_id, latency, False)
        except Exception as log_error:
            logger.error(f"Failed to log VPN error: {str(log_error)}")
        
        # Use comprehensive error handler
        context_data = {
            'latency_ms': latency,
            'vpc_endpoint_health': vpc_clients.get_health_status() if 'vpc_clients' in globals() else {},
            'path': event.get('path', ''),
            'http_method': event.get('httpMethod', 'POST')
        }
        
        return error_handler.handle_error(e, request_id, context_data)

def detect_routing_method(path):
    """
    Detect routing method from API Gateway path
    """
    if '/vpn/' in path:
        return 'vpn'
    return 'internet'  # Default fallback

def parse_request(event):
    """
    Parse API Gateway event to extract Bedrock request parameters
    """
    try:
        # Get the request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            raise ValueError("Missing request body")
        
        # Extract required Bedrock parameters
        model_id = body.get('modelId')
        if not model_id:
            raise ValueError("Missing required parameter: modelId")
        
        request_data = {
            'modelId': model_id,
            'contentType': body.get('contentType', 'application/json'),
            'accept': body.get('accept', 'application/json'),
            'body': body.get('body', ''),
            'sourceIP': event.get('requestContext', {}).get('identity', {}).get('sourceIp', 'unknown'),
            'userArn': event.get('requestContext', {}).get('identity', {}).get('userArn', 'unknown'),
            'routing_method': ROUTING_METHOD
        }
        
        return request_data
        
    except Exception as e:
        logger.error(f"Failed to parse request: {str(e)}")
        raise ValueError(f"Invalid request format: {str(e)}")

def get_commercial_credentials_vpc():
    """
    Retrieve commercial Bedrock credentials from Secrets Manager via VPC endpoint
    """
    try:
        secrets_client = vpc_clients.get_secrets_client()
        response = secrets_client.get_secret_value(SecretId=COMMERCIAL_CREDENTIALS_SECRET)
        secret_data = json.loads(response['SecretString'])
        
        # Check for bedrock_api_key (preferred format)
        if 'bedrock_api_key' in secret_data:
            return secret_data
        
        # Fallback to AWS credentials format if available
        required_keys = ['aws_access_key_id', 'aws_secret_access_key']
        for key in required_keys:
            if key not in secret_data:
                raise ValueError(f"Missing required credential: {key}")
        
        return secret_data
        
    except ClientError as e:
        logger.error(f"Failed to retrieve commercial credentials via VPC endpoint: {str(e)}")
        raise Exception("Unable to retrieve commercial credentials via VPC endpoint")
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in secrets: {str(e)}")
        raise Exception("Invalid credential format in Secrets Manager")

def get_commercial_credentials_vpc_with_retry(request_id, max_retries=3):
    """
    Retrieve commercial credentials with retry logic for VPC endpoint failures
    """
    for attempt in range(max_retries):
        try:
            return get_commercial_credentials_vpc()
        except Exception as e:
            if attempt < max_retries - 1:
                wait_time = (2 ** attempt) * 0.5  # Exponential backoff
                logger.warning(f"Request {request_id}: Credentials retrieval failed (attempt {attempt + 1}), retrying in {wait_time}s: {str(e)}")
                time.sleep(wait_time)
            else:
                logger.error(f"Request {request_id}: All credential retrieval attempts failed")
                raise Exception(f"Failed to retrieve credentials after {max_retries} attempts: {str(e)}")

def classify_vpn_error(error_message):
    """
    Classify VPN-related errors for better handling and troubleshooting
    Returns: (error_type, error_code, http_status_code)
    """
    error_lower = error_message.lower()
    
    if 'vpn tunnel' in error_lower or 'connection refused' in error_lower:
        return 'VPN_TUNNEL_DOWN', 'VPNTunnelUnavailable', 503
    elif 'vpc endpoint' in error_lower or 'endpoint_url' in error_lower:
        return 'VPC_ENDPOINT_FAILURE', 'VPCEndpointUnavailable', 503
    elif 'timeout' in error_lower:
        return 'VPN_TIMEOUT', 'VPNRequestTimeout', 504
    elif 'dns' in error_lower or 'name resolution' in error_lower:
        return 'DNS_RESOLUTION_FAILURE', 'DNSResolutionFailed', 502
    elif 'credentials' in error_lower or 'unauthorized' in error_lower:
        return 'AUTHENTICATION_FAILURE', 'AuthenticationFailed', 401
    elif 'throttl' in error_lower or 'rate limit' in error_lower:
        return 'RATE_LIMITING', 'RequestThrottled', 429
    elif 'bedrock' in error_lower and ('400' in error_lower or 'bad request' in error_lower):
        return 'BEDROCK_REQUEST_ERROR', 'InvalidBedrockRequest', 400
    else:
        return 'UNKNOWN_VPN_ERROR', 'UnknownVPNError', 500

def get_troubleshooting_info(error_type):
    """
    Provide troubleshooting information based on error type
    """
    troubleshooting_guide = {
        'VPN_TUNNEL_DOWN': {
            'description': 'VPN tunnel appears to be down or unreachable',
            'steps': [
                'Check VPN Gateway status in AWS Console',
                'Verify VPN tunnel configuration',
                'Check network connectivity between partitions',
                'Review VPN Gateway logs'
            ]
        },
        'VPC_ENDPOINT_FAILURE': {
            'description': 'VPC endpoint is unavailable or misconfigured',
            'steps': [
                'Check VPC endpoint status in AWS Console',
                'Verify VPC endpoint DNS resolution',
                'Check security group rules for VPC endpoint',
                'Verify route table configuration'
            ]
        },
        'VPN_TIMEOUT': {
            'description': 'Request timed out, possibly due to VPN latency',
            'steps': [
                'Check VPN tunnel latency and bandwidth',
                'Verify commercial Bedrock service availability',
                'Consider increasing Lambda timeout',
                'Check for network congestion'
            ]
        },
        'DNS_RESOLUTION_FAILURE': {
            'description': 'DNS resolution failed for VPN or VPC endpoints',
            'steps': [
                'Check VPC DNS settings',
                'Verify VPC endpoint DNS names',
                'Check Route 53 resolver configuration',
                'Verify security group DNS rules'
            ]
        },
        'AUTHENTICATION_FAILURE': {
            'description': 'Authentication failed with commercial Bedrock',
            'steps': [
                'Verify commercial credentials in Secrets Manager',
                'Check cross-account IAM role permissions',
                'Verify API key validity and permissions',
                'Check Bedrock service permissions'
            ]
        }
    }
    
    return troubleshooting_guide.get(error_type, {
        'description': 'Unknown VPN-related error',
        'steps': [
            'Check CloudWatch logs for detailed error information',
            'Verify VPN and VPC endpoint configuration',
            'Contact support with request ID'
        ]
    })

def forward_to_bedrock_vpn_enhanced(commercial_creds, request_data, request_id):
    """
    Enhanced VPN routing with better error handling and retry logic
    """
    max_retries = 2
    
    for attempt in range(max_retries + 1):
        try:
            return forward_to_bedrock_vpn(commercial_creds, request_data)
        except Exception as e:
            error_type, _, _ = classify_vpn_error(str(e))
            
            # Don't retry certain error types
            if error_type in ['AUTHENTICATION_FAILURE', 'BEDROCK_REQUEST_ERROR']:
                raise e
            
            if attempt < max_retries:
                wait_time = (2 ** attempt) * 0.5
                logger.warning(f"Request {request_id}: VPN routing failed (attempt {attempt + 1}), retrying in {wait_time}s: {str(e)}")
                time.sleep(wait_time)
            else:
                logger.error(f"Request {request_id}: All VPN routing attempts failed")
                raise e

@lru_cache(maxsize=100)
def get_inference_profile_id(model_id: str) -> Optional[str]:
    """
    Get the inference profile ID for models that require it
    Maps model IDs to their corresponding system-defined inference profile IDs
    """
    # Mapping of model IDs to their inference profile IDs
    model_to_profile_map = {
        # Claude models
        'anthropic.claude-3-5-sonnet-20241022-v2:0': 'us.anthropic.claude-3-5-sonnet-20241022-v2:0',
        'anthropic.claude-3-5-sonnet-20240620-v1:0': 'us.anthropic.claude-3-5-sonnet-20240620-v1:0',
        'anthropic.claude-3-5-haiku-20241022-v1:0': 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
        'anthropic.claude-3-opus-20240229-v1:0': 'us.anthropic.claude-3-opus-20240229-v1:0',
        'anthropic.claude-3-sonnet-20240229-v1:0': 'us.anthropic.claude-3-sonnet-20240229-v1:0',
        'anthropic.claude-3-haiku-20240307-v1:0': 'us.anthropic.claude-3-haiku-20240307-v1:0',
    }
    
    return model_to_profile_map.get(model_id)

def forward_to_bedrock_vpn(commercial_creds, request_data):
    """
    Forward the request to commercial Bedrock via VPN
    """
    try:
        # Get model ID and body data
        model_id = request_data['modelId']
        body_data = request_data['body']
        
        # Parse and enhance the body data for Anthropic models
        if isinstance(body_data, str):
            try:
                body_dict = json.loads(body_data)
            except json.JSONDecodeError:
                body_dict = {}
        elif isinstance(body_data, dict):
            body_dict = body_data.copy()
        else:
            body_dict = {}
        
        # Add required anthropic_version for Anthropic models
        if 'anthropic' in model_id.lower():
            body_dict['anthropic_version'] = 'bedrock-2023-05-31'
            logger.info(f"Added anthropic_version for model {model_id}")
        
        # Convert back to JSON string
        body_json = json.dumps(body_dict)
        
        # Check if we have a Bedrock API key (preferred method for cross-partition)
        if 'bedrock_api_key' in commercial_creds:
            return forward_with_api_key_vpn(commercial_creds['bedrock_api_key'], model_id, body_json)
        else:
            return forward_with_aws_credentials_vpn(commercial_creds, model_id, body_json)
        
    except Exception as e:
        logger.error(f"Unexpected error calling Bedrock via VPN: {str(e)}")
        raise Exception(f"Failed to call commercial Bedrock via VPN: {str(e)}")

def forward_with_api_key_vpn(api_key, model_id, body_json):
    """Forward request using Bedrock API key via VPN with urllib"""
    try:
        import base64
        
        # Decode the base64 API key if needed
        try:
            decoded_key = base64.b64decode(api_key).decode('utf-8')
            # If it decodes successfully and looks like a key, use it
            if ':' in decoded_key and ('AKIA' in decoded_key or 'bedrock' in decoded_key):
                api_key = decoded_key
        except:
            # If decoding fails, use the original key
            pass
        
        # Use commercial Bedrock endpoint via VPN
        if COMMERCIAL_BEDROCK_ENDPOINT:
            url = f"{COMMERCIAL_BEDROCK_ENDPOINT}/model/{model_id}/invoke"
        else:
            # Default to standard endpoint (will route via VPN)
            url = f"https://bedrock-runtime.us-east-1.amazonaws.com/model/{model_id}/invoke"
        
        # Create request with headers
        req = urllib.request.Request(url, data=body_json.encode('utf-8'))
        req.add_header('Content-Type', 'application/json')
        req.add_header('Authorization', f'Bearer {api_key}')
        req.add_header('X-Routing-Method', 'vpn')
        
        # Make the request with VPN-appropriate timeout
        with urllib.request.urlopen(req, timeout=60) as response:
            response_body = response.read().decode('utf-8')
            content_type = response.headers.get('content-type', 'application/json')
            
            return {
                'body': response_body,
                'contentType': content_type,
                'routing_method': 'vpn',
                'endpoint_used': url
            }
        
    except urllib.error.HTTPError as e:
        status_code = e.code
        error_message = e.read().decode('utf-8')
        logger.error(f"Bedrock API HTTP error via VPN: {status_code} - {error_message}")
        
        if status_code == 400:
            raise Exception(f"Invalid request parameters: {error_message}")
        elif status_code == 403:
            raise Exception(f"Access denied to commercial Bedrock via VPN: {error_message}")
        elif status_code == 429:
            raise Exception(f"Request throttled by commercial Bedrock: {error_message}")
        else:
            raise Exception(f"Commercial Bedrock error via VPN ({status_code}): {error_message}")
    except urllib.error.URLError as e:
        if "timeout" in str(e).lower():
            raise Exception("Request timeout - VPN connection may be slow or unavailable")
        else:
            raise Exception(f"Connection error - VPN tunnel may be down: {str(e)}")
    except Exception as e:
        logger.error(f"Error with API key approach via VPN: {str(e)}")
        raise e

def forward_with_aws_credentials_vpn(commercial_creds, model_id, body_json):
    """Forward request using AWS credentials via VPN"""
    try:
        # Create AWS session with commercial credentials
        session = boto3.Session(
            aws_access_key_id=commercial_creds['aws_access_key_id'],
            aws_secret_access_key=commercial_creds['aws_secret_access_key'],
            region_name=commercial_creds.get('region', 'us-east-1')
        )
        
        # Create Bedrock Runtime client with VPN-optimized configuration
        bedrock_client = session.client(
            'bedrock-runtime', 
            region_name='us-east-1',
            config=boto3.session.Config(
                read_timeout=60,  # Increased timeout for VPN
                connect_timeout=10,
                retries={'max_attempts': 3}
            )
        )
        
        try:
            # Try direct model invocation first
            response = bedrock_client.invoke_model(
                modelId=model_id,
                contentType='application/json',
                accept='application/json',
                body=body_json
            )
            
            # Read the response
            response_body = response['body'].read().decode('utf-8')
            
            return {
                'body': response_body,
                'contentType': response.get('contentType', 'application/json'),
                'routing_method': 'vpn',
                'aws_credentials_used': True
            }
            
        except Exception as e:
            error_str = str(e)
            if "inference profile" in error_str.lower() or "on-demand throughput" in error_str.lower():
                # Model requires inference profile, use the system-defined one
                logger.info(f"Model {model_id} requires inference profile, looking up system-defined profile")
                
                profile_id = get_inference_profile_id(model_id)
                if profile_id:
                    logger.info(f"Retrying with inference profile: {profile_id}")
                    response = bedrock_client.invoke_model(
                        modelId=profile_id,
                        contentType='application/json',
                        accept='application/json',
                        body=body_json
                    )
                    
                    response_body = response['body'].read().decode('utf-8')
                    
                    return {
                        'body': response_body,
                        'contentType': response.get('contentType', 'application/json'),
                        'routing_method': 'vpn',
                        'aws_credentials_used': True,
                        'inference_profile_used': profile_id
                    }
                else:
                    logger.error(f"No inference profile mapping found for model: {model_id}")
            
            # Re-raise the original exception
            raise e
        
    except Exception as e:
        logger.error(f"Error with AWS credentials approach via VPN: {str(e)}")
        raise e

def log_request_vpc(request_id, request_data, response, latency, success, error_message=None):
    """
    Log request details to DynamoDB via VPC endpoint for dashboard
    """
    try:
        dynamodb = vpc_clients.get_dynamodb_resource()
        table = dynamodb.Table(REQUEST_LOG_TABLE)
        
        # Calculate request and response sizes
        request_size = len(json.dumps(request_data).encode('utf-8'))
        response_size = len(json.dumps(response).encode('utf-8')) if response else 0
        
        # Create log entry with VPN-specific metadata
        log_entry = {
            'requestId': request_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'sourcePartition': 'govcloud',
            'destinationPartition': 'commercial',
            'routingMethod': ROUTING_METHOD,
            'vpcEndpointsUsed': True,
            'modelId': request_data.get('modelId', 'unknown'),
            'userArn': request_data.get('userArn', 'unknown'),
            'sourceIP': request_data.get('sourceIP', 'unknown'),
            'requestSize': request_size,
            'responseSize': response_size,
            'latency': latency,
            'success': success,
            'statusCode': 200 if success else 500,
            'ttl': int(time.time()) + (30 * 24 * 60 * 60)  # 30 days TTL
        }
        
        if error_message:
            log_entry['errorMessage'] = error_message
        
        # Add VPN-specific metadata if available
        if response and isinstance(response, dict):
            log_entry['endpointUsed'] = response.get('endpoint_used', 'unknown')
            log_entry['awsCredentialsUsed'] = response.get('aws_credentials_used', False)
            log_entry['inferenceProfileUsed'] = response.get('inference_profile_used')
        
        # Write to DynamoDB via VPC endpoint
        table.put_item(Item=log_entry)
        logger.info(f"Request {request_id}: Logged to DynamoDB via VPC endpoint")
        
    except Exception as e:
        logger.error(f"Failed to log request to DynamoDB via VPC endpoint: {str(e)}")
        # Don't raise exception - logging failure shouldn't break the main flow

def send_custom_metrics(request_id, latency, success, error_type=None):
    """
    Send custom metrics to CloudWatch via VPC endpoint with error type tracking
    """
    try:
        cloudwatch = vpc_clients.get_cloudwatch_client()
        
        metrics = [
            {
                'MetricName': 'CrossPartitionRequests',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'RoutingMethod', 'Value': ROUTING_METHOD},
                    {'Name': 'SourcePartition', 'Value': 'govcloud'},
                    {'Name': 'DestinationPartition', 'Value': 'commercial'},
                    {'Name': 'Success', 'Value': str(success)}
                ]
            },
            {
                'MetricName': 'CrossPartitionLatency',
                'Value': latency,
                'Unit': 'Milliseconds',
                'Dimensions': [
                    {'Name': 'RoutingMethod', 'Value': ROUTING_METHOD},
                    {'Name': 'SourcePartition', 'Value': 'govcloud'},
                    {'Name': 'DestinationPartition', 'Value': 'commercial'}
                ]
            }
        ]
        
        # Add error-specific metrics if request failed
        if not success and error_type:
            metrics.append({
                'MetricName': 'VPNErrors',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'RoutingMethod', 'Value': ROUTING_METHOD},
                    {'Name': 'ErrorType', 'Value': error_type},
                    {'Name': 'SourcePartition', 'Value': 'govcloud'},
                    {'Name': 'DestinationPartition', 'Value': 'commercial'}
                ]
            })
        
        # Add VPC endpoint health metrics
        health_status = vpc_clients.get_health_status()
        for endpoint_name, status in health_status.items():
            metrics.append({
                'MetricName': 'VPCEndpointHealth',
                'Value': 1 if status.get('healthy', False) else 0,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'RoutingMethod', 'Value': ROUTING_METHOD},
                    {'Name': 'EndpointName', 'Value': endpoint_name}
                ]
            })
        
        # Send metrics via VPC endpoint
        cloudwatch.put_metric_data(
            Namespace='CrossPartition/DualRouting',
            MetricData=[{
                'MetricName': metric['MetricName'],
                'Value': metric['Value'],
                'Unit': metric['Unit'],
                'Dimensions': metric['Dimensions'],
                'Timestamp': datetime.utcnow()
            } for metric in metrics]
        )
        
        logger.info(f"Request {request_id}: Sent custom metrics via VPC endpoint (success: {success}, error_type: {error_type})")
        
    except Exception as e:
        logger.error(f"Failed to send custom metrics via VPC endpoint: {str(e)}")

def get_available_models(event, context):
    """
    Get available Bedrock models from commercial partition via VPN
    """
    try:
        # Get commercial AWS credentials via VPC endpoint
        commercial_creds = get_commercial_credentials_vpc()
        
        # Create AWS session with commercial credentials
        session = boto3.Session(
            aws_access_key_id=commercial_creds['aws_access_key_id'],
            aws_secret_access_key=commercial_creds['aws_secret_access_key'],
            region_name=commercial_creds.get('region', 'us-east-1')
        )
        
        # Create Bedrock client with VPN-optimized configuration
        bedrock_client = session.client(
            'bedrock', 
            region_name='us-east-1',
            config=boto3.session.Config(
                read_timeout=60,
                connect_timeout=10,
                retries={'max_attempts': 3}
            )
        )
        
        # List foundation models
        response = bedrock_client.list_foundation_models()
        
        # Process the models list
        models = []
        for model in response.get('modelSummaries', []):
            model_info = {
                'modelId': model.get('modelId'),
                'modelName': model.get('modelName'),
                'providerName': model.get('providerName'),
                'inputModalities': model.get('inputModalities', []),
                'outputModalities': model.get('outputModalities', []),
                'responseStreamingSupported': model.get('responseStreamingSupported', False),
                'customizationsSupported': model.get('customizationsSupported', []),
                'inferenceTypesSupported': model.get('inferenceTypesSupported', [])
            }
            models.append(model_info)
        
        # Get region information
        region_info = {
            'region': 'us-east-1',
            'partition': 'aws',
            'description': 'US East (N. Virginia) - Commercial AWS via VPN'
        }
        
        response_data = {
            'region': region_info,
            'models': models,
            'totalModels': len(models),
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'source': {
                'partition': 'AWS GovCloud',
                'region': 'us-gov-west-1',
                'requestId': context.aws_request_id,
                'routing_method': ROUTING_METHOD,
                'vpc_endpoints_used': True
            }
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
                'X-Routing-Method': ROUTING_METHOD
            },
            'body': json.dumps(response_data, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error getting available models via VPN: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'X-Routing-Method': ROUTING_METHOD
            },
            'body': json.dumps({
                'error': 'Failed to retrieve available models via VPN',
                'message': str(e),
                'region': 'us-east-1',
                'partition': 'aws',
                'routing_method': ROUTING_METHOD
            })
        }

def get_routing_info(event, context):
    """
    Return routing information for GET requests with VPN details
    """
    try:
        # Get request info
        source_ip = event.get('requestContext', {}).get('identity', {}).get('sourceIp', 'unknown')
        user_agent = event.get('headers', {}).get('User-Agent', 'unknown')
        request_id = context.aws_request_id
        
        # Return information about the VPN request routing
        response_data = {
            'message': 'Cross-Partition Inference Proxy via VPN (Dual Routing)',
            'status': 'operational',
            'routing': {
                'method': ROUTING_METHOD,
                'source': {
                    'partition': 'AWS GovCloud',
                    'region': 'us-gov-west-1',
                    'service': 'API Gateway + Lambda (VPC)',
                    'vpc_endpoints_used': True
                },
                'destination': {
                    'partition': 'AWS Commercial',
                    'region': 'us-east-1',
                    'service': 'Amazon Bedrock',
                    'access_method': 'VPN tunnel'
                },
                'flow': 'GovCloud API Gateway → GovCloud Lambda (VPC) → VPN Tunnel → Commercial Bedrock'
            },
            'vpc_configuration': {
                'secrets_manager_endpoint': bool(VPC_ENDPOINT_SECRETS),
                'dynamodb_endpoint': bool(VPC_ENDPOINT_DYNAMODB),
                'cloudwatch_logs_endpoint': bool(VPC_ENDPOINT_LOGS),
                'cloudwatch_metrics_endpoint': bool(VPC_ENDPOINT_MONITORING),
                'commercial_bedrock_endpoint': bool(COMMERCIAL_BEDROCK_ENDPOINT)
            },
            'request_info': {
                'request_id': request_id,
                'source_ip': source_ip,
                'user_agent': user_agent,
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'current_region': os.environ.get('AWS_REGION', 'us-gov-west-1')
            },
            'endpoints': {
                'vpn_bedrock_proxy': event.get('requestContext', {}).get('domainName', '') + '/v1/vpn/bedrock/invoke-model',
                'methods': ['GET (info)', 'POST (inference)']
            },
            'configuration': {
                'secrets_manager_secret': COMMERCIAL_CREDENTIALS_SECRET,
                'dynamodb_table': REQUEST_LOG_TABLE,
                'routing_method': ROUTING_METHOD
            }
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
                'X-Routing-Method': ROUTING_METHOD
            },
            'body': json.dumps(response_data, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error generating VPN routing info: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'X-Routing-Method': ROUTING_METHOD
            },
            'body': json.dumps({
                'error': 'Failed to generate VPN routing information',
                'message': str(e),
                'routing_method': ROUTING_METHOD
            })
        }