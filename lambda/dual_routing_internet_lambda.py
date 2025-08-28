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

# Import error handling system
from dual_routing_error_handler import (
    ErrorHandler, DualRoutingError, NetworkError, 
    AuthenticationError, ValidationError, ServiceError,
    validate_request, handle_lambda_error
)

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secrets_client = boto3.client('secretsmanager')
dynamodb = boto3.resource('dynamodb')

# Environment variables
COMMERCIAL_CREDENTIALS_SECRET = os.environ.get('COMMERCIAL_CREDENTIALS_SECRET', 'cross-partition-commercial-creds')
REQUEST_LOG_TABLE = os.environ.get('REQUEST_LOG_TABLE', 'cross-partition-requests')
ROUTING_METHOD = 'internet'

def lambda_handler(event, context):
    """
    Main Lambda handler for internet-routed cross-partition Bedrock requests
    Enhanced with comprehensive error handling system
    """
    request_id = str(uuid.uuid4())
    start_time = time.time()
    error_handler = ErrorHandler(ROUTING_METHOD)
    
    try:
        # Detect routing method from API Gateway path
        path = event.get('path', '')
        detected_routing = detect_routing_method(path)
        logger.info(f"Request {request_id}: Internet Lambda - Detected routing method: {detected_routing} from path: {path}")
        
        # Validate this is an internet request (for dual routing architecture)
        if detected_routing == 'vpn':
            raise ValidationError(
                message='This Lambda function only handles internet routing requests',
                routing_method=ROUTING_METHOD,
                details={
                    'expected_path': '/v1/bedrock/invoke-model',
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
        
        # Parse the incoming request
        request_data = parse_request(event)
        logger.info(f"Request {request_id}: Parsed request for model {request_data.get('modelId')}")
        
        # Get Bedrock bearer token
        try:
            bearer_token = get_bedrock_bearer_token()
            logger.info(f"Request {request_id}: Retrieved Bedrock bearer token")
        except Exception as token_error:
            raise AuthenticationError(
                message='Failed to retrieve Bedrock bearer token',
                routing_method=ROUTING_METHOD,
                details={'token_error': str(token_error)}
            )
        
        # Forward request to commercial Bedrock via internet using bearer token
        try:
            response = make_bedrock_request(bearer_token, request_data['modelId'], request_data['body'])
            logger.info(f"Request {request_id}: Successfully forwarded to commercial Bedrock via internet")
        except Exception as bedrock_error:
            # Check if it's a network error
            if any(keyword in str(bedrock_error).lower() for keyword in ['timeout', 'connection', 'network']):
                raise NetworkError(
                    message='Network error occurred while connecting to commercial Bedrock',
                    routing_method=ROUTING_METHOD,
                    details={'bedrock_error': str(bedrock_error)}
                )
            else:
                raise ServiceError(
                    message='Failed to forward request to commercial Bedrock',
                    routing_method=ROUTING_METHOD,
                    details={'bedrock_error': str(bedrock_error)}
                )
        
        # Calculate latency
        latency = int((time.time() - start_time) * 1000)  # milliseconds
        
        # Log request to DynamoDB
        log_request(request_id, request_data, response, latency, True)
        
        # Send custom metrics
        send_custom_metrics(request_id, latency, True)
        
        # Return successful response with routing method metadata
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': request_id,
                'X-Source-Partition': 'govcloud',
                'X-Destination-Partition': 'commercial',
                'X-Routing-Method': ROUTING_METHOD
            },
            'body': json.dumps({
                **response,
                'routing_method': ROUTING_METHOD
            })
        }
        
    except Exception as e:
        # Calculate latency for failed request
        latency = int((time.time() - start_time) * 1000)
        
        # Log failed request to DynamoDB
        try:
            request_data = parse_request(event) if 'request_data' not in locals() else request_data
            log_request(request_id, request_data, None, latency, False, str(e))
            send_custom_metrics(request_id, latency, False)
        except Exception as log_error:
            logger.error(f"Failed to log internet routing error: {str(log_error)}")
        
        # Use comprehensive error handler
        context_data = {
            'latency_ms': latency,
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
    return 'internet'  # Default for backward compatibility

def parse_request(event):
    """
    Parse API Gateway event to extract Bedrock request parameters
    Enhanced for dual routing with routing method detection
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
        
        # Detect routing method from path
        path = event.get('path', '')
        routing_method = detect_routing_method(path)
        
        request_data = {
            'modelId': model_id,
            'contentType': body.get('contentType', 'application/json'),
            'accept': body.get('accept', 'application/json'),
            'body': body.get('body', ''),
            'sourceIP': event.get('requestContext', {}).get('identity', {}).get('sourceIp', 'unknown'),
            'userArn': event.get('requestContext', {}).get('identity', {}).get('userArn', 'unknown'),
            'routing_method': routing_method,
            'api_path': path
        }
        
        return request_data
        
    except Exception as e:
        logger.error(f"Failed to parse request: {str(e)}")
        raise ValueError(f"Invalid request format: {str(e)}")

def get_bedrock_bearer_token():
    """
    Retrieve Bedrock bearer token from environment variable or Secrets Manager
    """
    # First try environment variable (for local testing)
    bearer_token = os.environ.get('AWS_BEARER_TOKEN_BEDROCK')
    if bearer_token:
        logger.info("Using bearer token from environment variable")
        return bearer_token
    
    # Fall back to Secrets Manager
    try:
        response = secrets_client.get_secret_value(SecretId=COMMERCIAL_CREDENTIALS_SECRET)
        secret_data = json.loads(response['SecretString'])
        
        bearer_token = secret_data.get('bedrock_bearer_token')
        if not bearer_token:
            raise ValueError("Bearer token not found in secrets")
        
        logger.info("Using bearer token from Secrets Manager")
        return bearer_token
        
    except ClientError as e:
        logger.error(f"Failed to retrieve bearer token from Secrets Manager: {str(e)}")
        raise Exception("Unable to retrieve Bedrock bearer token")
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in secrets: {str(e)}")
        raise Exception("Invalid credential format in Secrets Manager")

def make_bedrock_request(bearer_token, model_id, request_body):
    """
    Make direct HTTP request to Bedrock using bearer token authentication
    """
    try:
        # Bedrock endpoint URL
        bedrock_url = f"https://bedrock-runtime.us-east-1.amazonaws.com/model/{model_id}/invoke"
        
        headers = {
            'Authorization': f'Bearer {bearer_token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }
        
        # Make HTTP request to Bedrock
        req = urllib.request.Request(
            bedrock_url,
            data=json.dumps(request_body).encode('utf-8'),
            headers=headers,
            method='POST'
        )
        
        with urllib.request.urlopen(req, timeout=30) as response:
            response_data = json.loads(response.read().decode('utf-8'))
            return response_data
            
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8') if e.fp else 'No error details'
        logger.error(f"Bedrock HTTP error {e.code}: {error_body}")
        raise Exception(f"Bedrock request failed: {e.code} - {error_body}")
    except urllib.error.URLError as e:
        logger.error(f"Bedrock URL error: {str(e)}")
        raise Exception(f"Network error accessing Bedrock: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error in Bedrock request: {str(e)}")
        raise Exception(f"Failed to invoke Bedrock model: {str(e)}")
        
    except Exception as e:
        logger.error(f"Failed to create Bedrock session: {str(e)}")
        raise Exception("Unable to create Bedrock session")

def get_inference_profile_id(model_id):
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

def forward_to_bedrock(commercial_creds, request_data):
    """
    Forward the request to commercial Bedrock using AWS SDK via internet
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
            return forward_with_api_key(commercial_creds['bedrock_api_key'], model_id, body_json)
        else:
            return forward_with_aws_credentials(commercial_creds, model_id, body_json)
        
    except Exception as e:
        logger.error(f"Unexpected error calling Bedrock via internet: {str(e)}")
        raise Exception(f"Failed to call commercial Bedrock via internet: {str(e)}")

def forward_with_api_key(api_key, model_id, body_json):
    """Forward request using Bedrock API key with urllib via internet"""
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
        
        # Create the request
        url = f"https://bedrock-runtime.us-east-1.amazonaws.com/model/{model_id}/invoke"
        
        # Create request with headers
        req = urllib.request.Request(url, data=body_json.encode('utf-8'))
        req.add_header('Content-Type', 'application/json')
        req.add_header('Authorization', f'Bearer {api_key}')
        req.add_header('X-Routing-Method', 'internet')
        
        # Make the request
        with urllib.request.urlopen(req, timeout=30) as response:
            response_body = response.read().decode('utf-8')
            content_type = response.headers.get('content-type', 'application/json')
            
            return {
                'body': response_body,
                'contentType': content_type,
                'routing_method': 'internet',
                'endpoint_used': url
            }
        
    except urllib.error.HTTPError as e:
        status_code = e.code
        error_message = e.read().decode('utf-8')
        logger.error(f"Bedrock API HTTP error via internet: {status_code} - {error_message}")
        
        if status_code == 400:
            raise Exception(f"Invalid request parameters: {error_message}")
        elif status_code == 403:
            raise Exception(f"Access denied to commercial Bedrock: {error_message}")
        elif status_code == 429:
            raise Exception(f"Request throttled by commercial Bedrock: {error_message}")
        else:
            raise Exception(f"Commercial Bedrock error via internet ({status_code}): {error_message}")
    except Exception as e:
        logger.error(f"Error with API key approach via internet: {str(e)}")
        raise e

def forward_with_aws_credentials(commercial_creds, model_id, body_json):
    """Forward request using AWS credentials via internet"""
    try:
        # Create AWS session with commercial credentials
        session = create_bedrock_session(commercial_creds)
        
        # Create Bedrock Runtime client
        bedrock_client = session.client('bedrock-runtime', region_name='us-east-1')
        
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
                'routing_method': 'internet',
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
                        'routing_method': 'internet',
                        'aws_credentials_used': True,
                        'inference_profile_used': profile_id
                    }
                else:
                    logger.error(f"No inference profile mapping found for model: {model_id}")
            
            # Re-raise the original exception
            raise e
        
    except Exception as e:
        logger.error(f"Error with AWS credentials approach via internet: {str(e)}")
        raise e

def log_request(request_id, request_data, response, latency, success, error_message=None):
    """
    Log request details to DynamoDB for dashboard
    Enhanced for dual routing with routing method tracking
    """
    try:
        table = dynamodb.Table(REQUEST_LOG_TABLE)
        
        # Calculate request and response sizes
        request_size = len(json.dumps(request_data).encode('utf-8'))
        response_size = len(json.dumps(response).encode('utf-8')) if response else 0
        
        # Create log entry with internet routing metadata
        log_entry = {
            'requestId': request_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'sourcePartition': 'govcloud',
            'destinationPartition': 'commercial',
            'routingMethod': ROUTING_METHOD,
            'modelId': request_data.get('modelId', 'unknown'),
            'userArn': request_data.get('userArn', 'unknown'),
            'sourceIP': request_data.get('sourceIP', 'unknown'),
            'apiPath': request_data.get('api_path', 'unknown'),
            'requestSize': request_size,
            'responseSize': response_size,
            'latency': latency,
            'success': success,
            'statusCode': 200 if success else 500,
            'ttl': int(time.time()) + (30 * 24 * 60 * 60)  # 30 days TTL
        }
        
        if error_message:
            log_entry['errorMessage'] = error_message
        
        # Add internet routing specific metadata if available
        if response and isinstance(response, dict):
            log_entry['endpointUsed'] = response.get('endpoint_used', 'unknown')
            log_entry['awsCredentialsUsed'] = response.get('aws_credentials_used', False)
            log_entry['inferenceProfileUsed'] = response.get('inference_profile_used')
        
        # Write to DynamoDB
        table.put_item(Item=log_entry)
        logger.info(f"Request {request_id}: Logged to DynamoDB")
        
    except Exception as e:
        logger.error(f"Failed to log request to DynamoDB: {str(e)}")
        # Don't raise exception - logging failure shouldn't break the main flow

def send_custom_metrics(request_id, latency, success):
    """
    Send custom metrics to CloudWatch for internet routing
    """
    try:
        cloudwatch = boto3.client('cloudwatch')
        
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
        
        # Send metrics
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
        
        logger.info(f"Request {request_id}: Sent custom metrics for internet routing")
        
    except Exception as e:
        logger.error(f"Failed to send custom metrics: {str(e)}")

def get_available_models(event, context):
    """
    Get available Bedrock models from commercial partition using AWS credentials via internet
    """
    try:
        # Get commercial AWS credentials
        commercial_creds = get_commercial_credentials()
        
        # Create AWS session with commercial credentials
        session = create_bedrock_session(commercial_creds)
        
        # Create Bedrock client
        bedrock_client = session.client('bedrock', region_name='us-east-1')
        
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
            'description': 'US East (N. Virginia) - Commercial AWS via Internet'
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
                'routing_method': ROUTING_METHOD
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
        logger.error(f"Error getting available models via internet: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'X-Routing-Method': ROUTING_METHOD
            },
            'body': json.dumps({
                'error': 'Failed to retrieve available models via internet',
                'message': str(e),
                'region': 'us-east-1',
                'partition': 'aws',
                'routing_method': ROUTING_METHOD
            })
        }

def get_routing_info(event, context):
    """
    Return routing information for GET requests with internet routing details
    """
    try:
        # Get request info
        source_ip = event.get('requestContext', {}).get('identity', {}).get('sourceIp', 'unknown')
        user_agent = event.get('headers', {}).get('User-Agent', 'unknown')
        request_id = context.aws_request_id
        
        # Return information about the internet request routing
        response_data = {
            'message': 'Cross-Partition Inference Proxy via Internet (Dual Routing)',
            'status': 'operational',
            'routing': {
                'method': ROUTING_METHOD,
                'source': {
                    'partition': 'AWS GovCloud',
                    'region': 'us-gov-west-1',
                    'service': 'API Gateway + Lambda'
                },
                'destination': {
                    'partition': 'AWS Commercial',
                    'region': 'us-east-1',
                    'service': 'Amazon Bedrock',
                    'access_method': 'Internet'
                },
                'flow': 'GovCloud API Gateway → GovCloud Lambda → Internet → Commercial Bedrock'
            },
            'request_info': {
                'request_id': request_id,
                'source_ip': source_ip,
                'user_agent': user_agent,
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'current_region': os.environ.get('AWS_REGION', 'us-gov-west-1')
            },
            'endpoints': {
                'internet_bedrock_proxy': event.get('requestContext', {}).get('domainName', '') + '/v1/bedrock/invoke-model',
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
        logger.error(f"Error generating internet routing info: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'X-Routing-Method': ROUTING_METHOD
            },
            'body': json.dumps({
                'error': 'Failed to generate internet routing information',
                'message': str(e),
                'routing_method': ROUTING_METHOD
            })
        }