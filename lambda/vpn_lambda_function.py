import json
import boto3
import logging
import time
import uuid
import os
import requests
from datetime import datetime
from botocore.exceptions import ClientError, NoCredentialsError
from functools import lru_cache
from typing import Dict, Any, Optional

# Import performance optimizations
from performance_optimizations import (
    performance_optimized, 
    get_performance_optimizer,
    get_connection_pool,
    get_response_cache,
    cache_response,
    optimize_memory_usage
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
ROUTING_METHOD = os.environ.get('ROUTING_METHOD', 'vpn')

# Secrets and table configuration
COMMERCIAL_CREDENTIALS_SECRET = os.environ.get('COMMERCIAL_CREDENTIALS_SECRET', 'cross-partition-commercial-creds')
REQUEST_LOG_TABLE = os.environ.get('REQUEST_LOG_TABLE', 'cross-partition-requests')

class VPCEndpointConnectionPool:
    """Connection pool for VPC endpoint clients to avoid recreation"""
    
    def __init__(self):
        self._clients = {}
    
    @lru_cache(maxsize=10)
    def get_secrets_client(self):
        """Get Secrets Manager client configured for VPC endpoint"""
        if VPC_ENDPOINT_SECRETS:
            return boto3.client('secretsmanager', endpoint_url=VPC_ENDPOINT_SECRETS)
        return boto3.client('secretsmanager')
    
    @lru_cache(maxsize=10)
    def get_dynamodb_resource(self):
        """Get DynamoDB resource configured for VPC endpoint"""
        if VPC_ENDPOINT_DYNAMODB:
            return boto3.resource('dynamodb', endpoint_url=VPC_ENDPOINT_DYNAMODB)
        return boto3.resource('dynamodb')
    
    @lru_cache(maxsize=10)
    def get_logs_client(self):
        """Get CloudWatch Logs client configured for VPC endpoint"""
        if VPC_ENDPOINT_LOGS:
            return boto3.client('logs', endpoint_url=VPC_ENDPOINT_LOGS)
        return boto3.client('logs')
    
    @lru_cache(maxsize=10)
    def get_cloudwatch_client(self):
        """Get CloudWatch client configured for VPC endpoint"""
        if VPC_ENDPOINT_MONITORING:
            return boto3.client('cloudwatch', endpoint_url=VPC_ENDPOINT_MONITORING)
        return boto3.client('cloudwatch')

# Global connection pool instance
connection_pool = VPCEndpointConnectionPool()

@performance_optimized
def lambda_handler(event, context):
    """
    Main Lambda handler for cross-partition Bedrock requests via VPN
    Enhanced with performance optimizations for VPC deployment
    """
    request_id = str(uuid.uuid4())
    start_time = time.time()
    
    # Get performance optimizer from context
    optimizer = event.get('_performance_context', {}).get('optimizer')
    if optimizer:
        logger.info(f"Request {request_id}: Using performance optimizations")
    
    # Log VPC configuration for debugging
    logger.info(f"Request {request_id}: VPC endpoint configuration - "
                f"Secrets: {bool(VPC_ENDPOINT_SECRETS)}, "
                f"DynamoDB: {bool(VPC_ENDPOINT_DYNAMODB)}, "
                f"Routing: {ROUTING_METHOD}")
    
    # Check if this is a GET request
    http_method = event.get('httpMethod', 'POST')
    path = event.get('path', '')
    
    if http_method == 'GET':
        if 'models' in path:
            return get_available_models(event, context)
        else:
            return get_routing_info(event, context)
    
    try:
        # Parse the incoming request
        request_data = parse_request(event)
        logger.info(f"Request {request_id}: Parsed request for model {request_data.get('modelId')}")
        
        # Get commercial Bedrock API key via VPC endpoint
        commercial_creds = get_commercial_credentials_vpc()
        logger.info(f"Request {request_id}: Retrieved commercial API key via VPC endpoint")
        
        # Forward request to commercial Bedrock via VPN
        response = forward_to_bedrock_vpn(commercial_creds, request_data)
        logger.info(f"Request {request_id}: Successfully forwarded to commercial Bedrock via VPN")
        
        # Calculate latency
        latency = int((time.time() - start_time) * 1000)  # milliseconds
        
        # Log request to DynamoDB via VPC endpoint
        log_request_vpc(request_id, request_data, response, latency, True)
        
        # Send custom metrics via VPC endpoint
        send_custom_metrics(request_id, latency, True)
        
        # Optimize memory usage periodically
        if request_id.endswith('0'):  # Every ~10th request
            optimize_memory_usage()
        
        # Return successful response with VPN metadata
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': request_id,
                'X-Source-Partition': 'govcloud',
                'X-Destination-Partition': 'commercial',
                'X-Routing-Method': ROUTING_METHOD,
                'X-VPC-Endpoints-Used': 'true'
            },
            'body': json.dumps({
                **response,
                'metadata': {
                    'request_id': request_id,
                    'routing_method': ROUTING_METHOD,
                    'vpc_endpoints_used': True,
                    'latency_ms': latency,
                    'source_partition': 'govcloud',
                    'destination_partition': 'commercial'
                }
            })
        }
        
    except Exception as e:
        # Calculate latency for failed request
        latency = int((time.time() - start_time) * 1000)
        
        logger.error(f"Request {request_id}: Error - {str(e)}")
        
        # Log failed request to DynamoDB via VPC endpoint
        try:
            request_data = parse_request(event) if 'request_data' not in locals() else request_data
            log_request_vpc(request_id, request_data, None, latency, False, str(e))
            send_custom_metrics(request_id, latency, False)
        except Exception as log_error:
            logger.error(f"Failed to log error: {str(log_error)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': request_id,
                'X-Routing-Method': ROUTING_METHOD
            },
            'body': json.dumps({
                'error': {
                    'code': 'InternalError',
                    'message': 'Failed to process cross-partition request via VPN',
                    'requestId': request_id,
                    'routing_method': ROUTING_METHOD
                }
            })
        }

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
    Retrieve commercial Bedrock API key from Secrets Manager via VPC endpoint
    Enhanced with caching for performance
    """
    try:
        # Use performance optimizer for cached credentials
        optimizer = get_performance_optimizer()
        return optimizer.get_cached_credentials()
        
    except Exception as e:
        logger.error(f"Failed to retrieve commercial credentials via VPC endpoint: {str(e)}")
        raise Exception("Unable to retrieve commercial credentials via VPC endpoint")

def create_bedrock_session_vpc(credentials):
    """
    Create AWS session with commercial credentials for Bedrock access via VPN
    """
    try:
        # Create session with commercial AWS credentials
        # When using VPN, we'll route to commercial partition via private network
        session = boto3.Session(
            aws_access_key_id=credentials['aws_access_key_id'],
            aws_secret_access_key=credentials['aws_secret_access_key'],
            region_name=credentials.get('region', 'us-east-1')
        )
        
        return session
        
    except Exception as e:
        logger.error(f"Failed to create Bedrock session for VPN: {str(e)}")
        raise Exception("Unable to create Bedrock session for VPN routing")

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
        'anthropic.claude-opus-4-20250514-v1:0': 'us.anthropic.claude-opus-4-20250514-v1:0',
        'anthropic.claude-sonnet-4-20250514-v1:0': 'us.anthropic.claude-sonnet-4-20250514-v1:0',
        'anthropic.claude-3-7-sonnet-20250219-v1:0': 'us.anthropic.claude-3-7-sonnet-20250219-v1:0',
        'anthropic.claude-opus-4-1-20250805-v1:0': 'us.anthropic.claude-opus-4-1-20250805-v1:0',
        
        # Meta Llama models
        'meta.llama3-1-8b-instruct-v1:0': 'us.meta.llama3-1-8b-instruct-v1:0',
        'meta.llama3-1-70b-instruct-v1:0': 'us.meta.llama3-1-70b-instruct-v1:0',
        'meta.llama3-2-1b-instruct-v1:0': 'us.meta.llama3-2-1b-instruct-v1:0',
        'meta.llama3-2-3b-instruct-v1:0': 'us.meta.llama3-2-3b-instruct-v1:0',
        'meta.llama3-2-11b-instruct-v1:0': 'us.meta.llama3-2-11b-instruct-v1:0',
        'meta.llama3-2-90b-instruct-v1:0': 'us.meta.llama3-2-90b-instruct-v1:0',
        'meta.llama3-3-70b-instruct-v1:0': 'us.meta.llama3-3-70b-instruct-v1:0',
        'meta.llama4-scout-17b-instruct-v1:0': 'us.meta.llama4-scout-17b-instruct-v1:0',
        'meta.llama4-maverick-17b-instruct-v1:0': 'us.meta.llama4-maverick-17b-instruct-v1:0',
        
        # Amazon Nova models
        'amazon.nova-premier-v1:0': 'us.amazon.nova-premier-v1:0',
        'amazon.nova-pro-v1:0': 'us.amazon.nova-pro-v1:0',
        'amazon.nova-lite-v1:0': 'us.amazon.nova-lite-v1:0',
        'amazon.nova-micro-v1:0': 'us.amazon.nova-micro-v1:0',
        
        # Other models
        'deepseek.r1-v1:0': 'us.deepseek.r1-v1:0',
        'mistral.pixtral-large-2502-v1:0': 'us.mistral.pixtral-large-2502-v1:0',
        'twelvelabs.pegasus-1-2-v1:0': 'us.twelvelabs.pegasus-1-2-v1:0',
    }
    
    return model_to_profile_map.get(model_id)

def forward_to_bedrock_vpn(commercial_creds, request_data):
    """
    Forward the request to commercial Bedrock via VPN using API key or AWS SDK
    """
    try:
        # Get model ID and body data
        model_id = request_data['modelId']
        body_data = request_data['body']
        
        # Convert body to JSON string if it's a dict
        if isinstance(body_data, dict):
            body_json = json.dumps(body_data)
        else:
            body_json = body_data
        
        # Check if we have a Bedrock API key (preferred method for cross-partition)
        if 'bedrock_api_key' in commercial_creds:
            return forward_with_api_key_vpn(commercial_creds['bedrock_api_key'], model_id, body_json)
        else:
            return forward_with_aws_credentials_vpn(commercial_creds, model_id, body_json)
        
    except Exception as e:
        logger.error(f"Unexpected error calling Bedrock via VPN: {str(e)}")
        raise Exception(f"Failed to call commercial Bedrock via VPN: {str(e)}")

def forward_with_api_key_vpn(api_key, model_id, body_json):
    """Forward request using Bedrock API key via VPN"""
    try:
        # Decode the base64 API key if needed
        try:
            import base64
            decoded_key = base64.b64decode(api_key).decode('utf-8')
            # If it decodes successfully and looks like a key, use it
            if ':' in decoded_key and 'AKIA' in decoded_key:
                api_key = decoded_key
        except:
            # If decoding fails, use the original key
            pass
        
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {api_key}',
            'X-Routing-Method': 'vpn'
        }
        
        # Use commercial Bedrock endpoint via VPN
        if COMMERCIAL_BEDROCK_ENDPOINT:
            url = f"{COMMERCIAL_BEDROCK_ENDPOINT}/model/{model_id}/invoke"
        else:
            # Default to standard endpoint (will route via VPN)
            url = f"https://bedrock-runtime.us-east-1.amazonaws.com/model/{model_id}/invoke"
        
        # Configure timeout for VPN latency
        response = requests.post(url, headers=headers, data=body_json, timeout=60)
        response.raise_for_status()
        
        return {
            'body': response.text,
            'contentType': response.headers.get('content-type', 'application/json'),
            'routing_method': 'vpn',
            'endpoint_used': url
        }
        
    except requests.exceptions.HTTPError as e:
        status_code = e.response.status_code
        error_message = e.response.text
        logger.error(f"Bedrock API HTTP error via VPN: {status_code} - {error_message}")
        
        if status_code == 400:
            raise Exception(f"Invalid request parameters: {error_message}")
        elif status_code == 403:
            raise Exception(f"Access denied to commercial Bedrock via VPN: {error_message}")
        elif status_code == 429:
            raise Exception(f"Request throttled by commercial Bedrock: {error_message}")
        else:
            raise Exception(f"Commercial Bedrock error via VPN ({status_code}): {error_message}")
    except requests.exceptions.Timeout:
        raise Exception("Request timeout - VPN connection may be slow or unavailable")
    except requests.exceptions.ConnectionError:
        raise Exception("Connection error - VPN tunnel may be down")

def forward_with_aws_credentials_vpn(commercial_creds, model_id, body_json):
    """Forward request using AWS credentials via VPN"""
    try:
        # Create AWS session with commercial credentials
        session = create_bedrock_session_vpc(commercial_creds)
        
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
        dynamodb = connection_pool.get_dynamodb_resource()
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
        
        # Write to DynamoDB via VPC endpoint with retry logic
        max_retries = 3
        for attempt in range(max_retries):
            try:
                table.put_item(Item=log_entry)
                logger.info(f"Request {request_id}: Logged to DynamoDB via VPC endpoint")
                break
            except Exception as e:
                if attempt < max_retries - 1:
                    logger.warning(f"DynamoDB write failed (attempt {attempt + 1}), retrying: {str(e)}")
                    time.sleep(0.1 * (2 ** attempt))
                else:
                    raise e
        
    except Exception as e:
        logger.error(f"Failed to log request to DynamoDB via VPC endpoint: {str(e)}")
        # Don't raise exception - logging failure shouldn't break the main flow

def send_custom_metrics(request_id, latency, success):
    """
    Send custom metrics to CloudWatch via VPC endpoint
    """
    try:
        cloudwatch = connection_pool.get_cloudwatch_client()
        
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
        
        # Send metrics via VPC endpoint
        cloudwatch.put_metric_data(
            Namespace='CrossPartition/VPN',
            MetricData=[{
                'MetricName': metric['MetricName'],
                'Value': metric['Value'],
                'Unit': metric['Unit'],
                'Dimensions': metric['Dimensions'],
                'Timestamp': datetime.utcnow()
            } for metric in metrics]
        )
        
        logger.info(f"Request {request_id}: Sent custom metrics via VPC endpoint")
        
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
        session = create_bedrock_session_vpc(commercial_creds)
        
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
            'message': 'Cross-Partition Inference Proxy via VPN',
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
                'bedrock_proxy': event.get('requestContext', {}).get('domainName', '') + '/v1/bedrock/invoke-model',
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