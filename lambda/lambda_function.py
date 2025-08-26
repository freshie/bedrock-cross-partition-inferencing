import json
import boto3
import logging
import time
import uuid
import os
import requests
from datetime import datetime
from botocore.exceptions import ClientError, NoCredentialsError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
secrets_client = boto3.client('secretsmanager')
dynamodb = boto3.resource('dynamodb')

# Environment variables
COMMERCIAL_CREDENTIALS_SECRET = 'cross-partition-commercial-creds'
REQUEST_LOG_TABLE = 'cross-partition-requests'

def lambda_handler(event, context):
    """
    Main Lambda handler for cross-partition Bedrock requests
    """
    request_id = str(uuid.uuid4())
    start_time = time.time()
    
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
        
        # Get commercial Bedrock API key
        commercial_creds = get_commercial_credentials()
        logger.info(f"Request {request_id}: Retrieved commercial API key")
        
        # Forward request to commercial Bedrock
        response = forward_to_bedrock(commercial_creds, request_data)
        logger.info(f"Request {request_id}: Successfully forwarded to commercial Bedrock")
        
        # Calculate latency
        latency = int((time.time() - start_time) * 1000)  # milliseconds
        
        # Log request to DynamoDB
        log_request(request_id, request_data, response, latency, True)
        
        # Return successful response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': request_id,
                'X-Source-Partition': 'govcloud',
                'X-Destination-Partition': 'commercial'
            },
            'body': json.dumps(response)
        }
        
    except Exception as e:
        # Calculate latency for failed request
        latency = int((time.time() - start_time) * 1000)
        
        logger.error(f"Request {request_id}: Error - {str(e)}")
        
        # Log failed request to DynamoDB
        try:
            request_data = parse_request(event) if 'request_data' not in locals() else request_data
            log_request(request_id, request_data, None, latency, False, str(e))
        except:
            pass  # Don't fail on logging errors
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': request_id
            },
            'body': json.dumps({
                'error': {
                    'code': 'InternalError',
                    'message': 'Failed to process cross-partition request',
                    'requestId': request_id
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
            'userArn': event.get('requestContext', {}).get('identity', {}).get('userArn', 'unknown')
        }
        
        return request_data
        
    except Exception as e:
        logger.error(f"Failed to parse request: {str(e)}")
        raise ValueError(f"Invalid request format: {str(e)}")

def get_commercial_credentials():
    """
    Retrieve commercial Bedrock API key from Secrets Manager
    """
    try:
        response = secrets_client.get_secret_value(SecretId=COMMERCIAL_CREDENTIALS_SECRET)
        secret_data = json.loads(response['SecretString'])
        
        required_keys = ['bedrock_api_key']
        for key in required_keys:
            if key not in secret_data:
                raise ValueError(f"Missing required credential: {key}")
        
        # Check if API key is a placeholder
        if secret_data['bedrock_api_key'] == 'PLACEHOLDER_BEDROCK_API_KEY':
            raise ValueError("Commercial Bedrock API key not configured. Please update the secret with your actual API key.")
        
        return secret_data
        
    except ClientError as e:
        logger.error(f"Failed to retrieve commercial credentials: {str(e)}")
        raise Exception("Unable to retrieve commercial Bedrock API key")
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in secrets: {str(e)}")
        raise Exception("Invalid credential format in Secrets Manager")

def decode_bedrock_api_key(api_key):
    """
    Decode Bedrock API key to extract access key ID and secret access key
    """
    try:
        import base64
        
        # Decode the base64 API key
        decoded_key = base64.b64decode(api_key).decode('utf-8')
        
        # Split into access key ID and secret access key
        # Format: AccessKeyId:SecretAccessKey
        parts = decoded_key.split(':')
        if len(parts) != 2:
            raise ValueError("Invalid API key format")
        
        return {
            'access_key_id': parts[0],
            'secret_access_key': parts[1]
        }
        
    except Exception as e:
        logger.error(f"Failed to decode Bedrock API key: {str(e)}")
        raise Exception("Unable to decode Bedrock API key")

def forward_to_bedrock(commercial_creds, request_data):
    """
    Forward the request to commercial Bedrock using boto3 with decoded API key credentials
    """
    try:
        # Decode the Bedrock API key
        decoded_creds = decode_bedrock_api_key(commercial_creds['bedrock_api_key'])
        
        # Create a boto3 client for Bedrock Runtime in commercial partition
        bedrock_client = boto3.client(
            'bedrock-runtime',
            region_name='us-east-1',
            aws_access_key_id=decoded_creds['access_key_id'],
            aws_secret_access_key=decoded_creds['secret_access_key']
        )
        
        # Make the request to Bedrock
        response = bedrock_client.invoke_model(
            modelId=request_data['modelId'],
            contentType=request_data['contentType'],
            accept=request_data['accept'],
            body=request_data['body']
        )
        
        # Read the response body
        response_body = response['body'].read()
        
        # Return the response data
        return {
            'body': response_body.decode('utf-8'),
            'contentType': response['contentType']
        }
        
    except Exception as e:
        logger.error(f"Bedrock API error: {str(e)}")
        
        # Handle specific boto3 exceptions
        if 'AccessDeniedException' in str(e):
            raise Exception(f"Access denied to commercial Bedrock: {str(e)}")
        elif 'ValidationException' in str(e):
            raise Exception(f"Invalid request parameters: {str(e)}")
        elif 'ThrottlingException' in str(e):
            raise Exception(f"Request throttled by commercial Bedrock: {str(e)}")
        else:
            raise Exception(f"Failed to call commercial Bedrock: {str(e)}")

def log_request(request_id, request_data, response, latency, success, error_message=None):
    """
    Log request details to DynamoDB for dashboard
    """
    try:
        table = dynamodb.Table(REQUEST_LOG_TABLE)
        
        # Calculate request and response sizes
        request_size = len(json.dumps(request_data).encode('utf-8'))
        response_size = len(json.dumps(response).encode('utf-8')) if response else 0
        
        # Create log entry
        log_entry = {
            'requestId': request_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'sourcePartition': 'govcloud',
            'destinationPartition': 'commercial',
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
        
        # Write to DynamoDB
        table.put_item(Item=log_entry)
        logger.info(f"Request {request_id}: Logged to DynamoDB")
        
    except Exception as e:
        logger.error(f"Failed to log request to DynamoDB: {str(e)}")
        # Don't raise exception - logging failure shouldn't break the main flow

def get_available_models(event, context):
    """
    Get available Bedrock models from commercial partition using API key
    """
    try:
        # Get commercial Bedrock API key
        commercial_creds = get_commercial_credentials()
        
        # Decode the Bedrock API key
        decoded_creds = decode_bedrock_api_key(commercial_creds['bedrock_api_key'])
        
        # Create a boto3 client for Bedrock in commercial partition
        bedrock_client = boto3.client(
            'bedrock',
            region_name='us-east-1',
            aws_access_key_id=decoded_creds['access_key_id'],
            aws_secret_access_key=decoded_creds['secret_access_key']
        )
        
        # List foundation models
        response = bedrock_client.list_foundation_models()
        
        # Parse the response
        response_data = response
        
        # Process the models list
        models = []
        for model in response_data.get('modelSummaries', []):
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
            'description': 'US East (N. Virginia) - Commercial AWS'
        }
        
        response_data = {
            'region': region_info,
            'models': models,
            'totalModels': len(models),
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'source': {
                'partition': 'AWS GovCloud',
                'region': 'us-gov-west-1',
                'requestId': context.aws_request_id
            }
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,OPTIONS'
            },
            'body': json.dumps(response_data, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error getting available models: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Failed to retrieve available models',
                'message': str(e),
                'region': 'us-east-1',
                'partition': 'aws'
            })
        }

def get_routing_info(event, context):
    """
    Return routing information for GET requests
    """
    try:
        # Get request info
        source_ip = event.get('requestContext', {}).get('identity', {}).get('sourceIp', 'unknown')
        user_agent = event.get('headers', {}).get('User-Agent', 'unknown')
        request_id = context.aws_request_id
        
        # Return information about the request routing
        response_data = {
            'message': 'Cross-Partition Inference Proxy',
            'status': 'operational',
            'routing': {
                'source': {
                    'partition': 'AWS GovCloud',
                    'region': 'us-gov-west-1',
                    'service': 'API Gateway + Lambda'
                },
                'destination': {
                    'partition': 'AWS Commercial',
                    'region': 'us-east-1',
                    'service': 'Amazon Bedrock'
                },
                'flow': 'GovCloud API Gateway → GovCloud Lambda → Commercial Bedrock'
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
                'secrets_manager_secret': os.environ.get('COMMERCIAL_CREDENTIALS_SECRET', 'cross-partition-commercial-creds'),
                'dynamodb_table': os.environ.get('REQUEST_LOG_TABLE', 'cross-partition-requests')
            }
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps(response_data, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error generating routing info: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Failed to generate routing information',
                'message': str(e)
            })
        }