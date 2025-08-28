import json
import boto3
import logging
import time
import os
import base64
import hmac
import hashlib
from datetime import datetime, timedelta
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
SECRETS_MANAGER_SECRET = os.environ.get('AUTH_SECRETS_SECRET', 'dual-routing-auth-secrets')
ALLOWED_ROUTING_METHODS = os.environ.get('ALLOWED_ROUTING_METHODS', 'internet,vpn').split(',')
TOKEN_EXPIRY_MINUTES = int(os.environ.get('TOKEN_EXPIRY_MINUTES', '60'))

# Initialize AWS clients
secrets_client = boto3.client('secretsmanager')

def lambda_handler(event, context):
    """
    Lambda authorizer for dual routing API Gateway
    Supports multiple authentication methods and routing-specific authorization
    """
    try:
        # Extract token from event
        token = extract_token(event)
        if not token:
            logger.error("No authorization token provided")
            raise Exception('Unauthorized')
        
        # Extract method ARN and routing information
        method_arn = event['methodArn']
        routing_method = extract_routing_method(method_arn)
        
        logger.info(f"Authorizing request for routing method: {routing_method}")
        
        # Validate token and get principal
        principal_id, context_data = validate_token(token, routing_method)
        
        # Generate policy
        policy = generate_policy(principal_id, 'Allow', method_arn, routing_method, context_data)
        
        logger.info(f"Authorization successful for principal: {principal_id}")
        return policy
        
    except Exception as e:
        logger.error(f"Authorization failed: {str(e)}")
        # Return deny policy
        return generate_policy('user', 'Deny', event.get('methodArn', '*'), 'unknown', {})

def extract_token(event):
    """
    Extract authorization token from various sources
    """
    # Check Authorization header (Bearer token)
    auth_header = event.get('authorizationToken')
    if auth_header:
        if auth_header.startswith('Bearer '):
            return auth_header[7:]  # Remove 'Bearer ' prefix
        return auth_header
    
    # Check headers for API key
    headers = event.get('headers', {})
    if 'X-API-Key' in headers:
        return headers['X-API-Key']
    if 'x-api-key' in headers:
        return headers['x-api-key']
    
    # Check query parameters
    query_params = event.get('queryStringParameters') or {}
    if 'api_key' in query_params:
        return query_params['api_key']
    
    return None

def extract_routing_method(method_arn):
    """
    Extract routing method from method ARN
    """
    try:
        # Method ARN format: arn:aws:execute-api:region:account:api-id/stage/method/resource-path
        parts = method_arn.split('/')
        if len(parts) >= 4:
            resource_path = '/'.join(parts[3:])
            if '/vpn/' in resource_path:
                return 'vpn'
            elif '/bedrock/' in resource_path:
                return 'internet'
        return 'unknown'
    except Exception as e:
        logger.error(f"Failed to extract routing method: {str(e)}")
        return 'unknown'

def validate_token(token, routing_method):
    """
    Validate token and return principal ID and context data
    """
    try:
        # Get authentication secrets
        auth_secrets = get_auth_secrets()
        
        # Try different validation methods
        
        # Method 1: API Key validation
        if validate_api_key(token, auth_secrets, routing_method):
            return f"api-key-{routing_method}", {
                'auth_method': 'api_key',
                'routing_method': routing_method,
                'validated_at': datetime.utcnow().isoformat()
            }
        
        # Method 2: JWT token validation
        jwt_result = validate_jwt_token(token, auth_secrets, routing_method)
        if jwt_result:
            return jwt_result['principal_id'], {
                'auth_method': 'jwt',
                'routing_method': routing_method,
                'user_id': jwt_result.get('user_id'),
                'permissions': jwt_result.get('permissions', []),
                'validated_at': datetime.utcnow().isoformat()
            }
        
        # Method 3: Custom token validation
        custom_result = validate_custom_token(token, auth_secrets, routing_method)
        if custom_result:
            return custom_result['principal_id'], {
                'auth_method': 'custom',
                'routing_method': routing_method,
                'user_id': custom_result.get('user_id'),
                'permissions': custom_result.get('permissions', []),
                'validated_at': datetime.utcnow().isoformat()
            }
        
        raise Exception('Invalid token')
        
    except Exception as e:
        logger.error(f"Token validation failed: {str(e)}")
        raise Exception('Unauthorized')

def get_auth_secrets():
    """
    Retrieve authentication secrets from Secrets Manager
    """
    try:
        response = secrets_client.get_secret_value(SecretId=SECRETS_MANAGER_SECRET)
        return json.loads(response['SecretString'])
    except ClientError as e:
        logger.error(f"Failed to retrieve auth secrets: {str(e)}")
        raise Exception('Configuration error')

def validate_api_key(token, auth_secrets, routing_method):
    """
    Validate API key against stored keys
    """
    try:
        api_keys = auth_secrets.get('api_keys', {})
        
        # Check routing-specific keys
        routing_keys = api_keys.get(routing_method, [])
        if token in routing_keys:
            return True
        
        # Check admin keys (access to all routing methods)
        admin_keys = api_keys.get('admin', [])
        if token in admin_keys:
            return True
        
        return False
        
    except Exception as e:
        logger.error(f"API key validation failed: {str(e)}")
        return False

def validate_jwt_token(token, auth_secrets, routing_method):
    """
    Validate JWT token (simplified implementation)
    """
    try:
        # This is a simplified JWT validation
        # In production, use a proper JWT library like PyJWT
        
        jwt_secrets = auth_secrets.get('jwt', {})
        secret_key = jwt_secrets.get('secret_key')
        
        if not secret_key:
            return None
        
        # Basic JWT structure validation
        parts = token.split('.')
        if len(parts) != 3:
            return None
        
        header, payload, signature = parts
        
        # Decode payload (without signature verification for simplicity)
        try:
            payload_data = json.loads(base64.urlsafe_b64decode(payload + '=='))
        except:
            return None
        
        # Check expiration
        exp = payload_data.get('exp')
        if exp and datetime.utcfromtimestamp(exp) < datetime.utcnow():
            logger.warning("JWT token expired")
            return None
        
        # Check routing method permissions
        permissions = payload_data.get('permissions', [])
        if routing_method not in permissions and 'admin' not in permissions:
            logger.warning(f"JWT token lacks permission for routing method: {routing_method}")
            return None
        
        return {
            'principal_id': payload_data.get('sub', 'jwt-user'),
            'user_id': payload_data.get('user_id'),
            'permissions': permissions
        }
        
    except Exception as e:
        logger.error(f"JWT validation failed: {str(e)}")
        return None

def validate_custom_token(token, auth_secrets, routing_method):
    """
    Validate custom token format
    """
    try:
        custom_config = auth_secrets.get('custom_tokens', {})
        
        # Custom token format: base64(user_id:routing_method:timestamp:signature)
        try:
            decoded = base64.b64decode(token).decode('utf-8')
            parts = decoded.split(':')
            
            if len(parts) != 4:
                return None
            
            user_id, token_routing, timestamp, signature = parts
            
            # Verify routing method
            if token_routing != routing_method and token_routing != 'admin':
                return None
            
            # Verify timestamp (token expiry)
            token_time = datetime.fromisoformat(timestamp)
            if datetime.utcnow() - token_time > timedelta(minutes=TOKEN_EXPIRY_MINUTES):
                logger.warning("Custom token expired")
                return None
            
            # Verify signature
            secret_key = custom_config.get('secret_key', '')
            expected_signature = hmac.new(
                secret_key.encode(),
                f"{user_id}:{token_routing}:{timestamp}".encode(),
                hashlib.sha256
            ).hexdigest()
            
            if signature != expected_signature:
                logger.warning("Custom token signature invalid")
                return None
            
            return {
                'principal_id': f"custom-{user_id}",
                'user_id': user_id,
                'permissions': [token_routing] if token_routing != 'admin' else ['internet', 'vpn']
            }
            
        except Exception as decode_error:
            logger.error(f"Custom token decode failed: {str(decode_error)}")
            return None
        
    except Exception as e:
        logger.error(f"Custom token validation failed: {str(e)}")
        return None

def generate_policy(principal_id, effect, resource, routing_method, context_data):
    """
    Generate IAM policy for API Gateway
    """
    policy = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': resource
                }
            ]
        },
        'context': {
            'routing_method': routing_method,
            'auth_timestamp': str(int(time.time())),
            **context_data
        }
    }
    
    # Add usage plan information if available
    if effect == 'Allow':
        policy['usageIdentifierKey'] = f"{principal_id}-{routing_method}"
    
    return policy

def generate_token(user_id, routing_method, secret_key):
    """
    Helper function to generate custom tokens (for testing/admin use)
    """
    timestamp = datetime.utcnow().isoformat()
    signature = hmac.new(
        secret_key.encode(),
        f"{user_id}:{routing_method}:{timestamp}".encode(),
        hashlib.sha256
    ).hexdigest()
    
    token_data = f"{user_id}:{routing_method}:{timestamp}:{signature}"
    return base64.b64encode(token_data.encode()).decode()

# Test function for local development
def test_authorizer():
    """
    Test function for local development
    """
    test_event = {
        'type': 'TOKEN',
        'authorizationToken': 'Bearer test-token',
        'methodArn': 'arn:aws:execute-api:us-gov-west-1:123456789012:abcdef123/prod/POST/v1/vpn/bedrock/invoke-model'
    }
    
    test_context = type('Context', (), {
        'aws_request_id': 'test-request-id',
        'function_name': 'test-authorizer'
    })()
    
    result = lambda_handler(test_event, test_context)
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    test_authorizer()