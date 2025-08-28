# Design Document: Dual Routing API Gateway

## Overview

This design implements separate API Gateway paths for internet and VPN routing to Commercial Bedrock, providing clear separation of concerns while maintaining backward compatibility. The solution creates two distinct Lambda functions with dedicated API paths, enabling independent monitoring, scaling, and troubleshooting.

## Architecture

### High-Level Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   API Gateway   │    │  Internet Lambda │    │ Commercial      │
│                 │────│  (Existing)      │────│ Bedrock         │
│ /v1/bedrock/... │    │                  │    │ (via Internet)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │
         │              ┌──────────────────┐    ┌─────────────────┐
         │              │   VPN Lambda     │    │ Commercial      │
         └──────────────│  (New - in VPC)  │────│ Bedrock         │
           /v1/vpn/...  │                  │    │ (via VPN)       │
                        └──────────────────┘    └─────────────────┘
```

### Detailed Component Architecture

#### 1. API Gateway Configuration
- **Single API Gateway** with multiple resource paths
- **Internet Path**: `/v1/bedrock/invoke-model` → Internet Lambda
- **VPN Path**: `/v1/vpn/bedrock/invoke-model` → VPN Lambda
- **Shared Authentication**: Same API key/IAM authentication for both paths
- **Independent Throttling**: Separate rate limits per path

#### 2. Lambda Functions

##### Internet Lambda (Existing - Enhanced)
- **Location**: No VPC (internet access)
- **Function**: Routes to Commercial Bedrock via internet
- **Dependencies**: boto3, urllib (no external libraries)
- **Authentication**: API key or cross-account IAM role
- **Monitoring**: Existing CloudWatch logs and metrics

##### VPN Lambda (New)
- **Location**: Inside VPC with private subnets
- **Function**: Routes to Commercial Bedrock via VPN
- **Dependencies**: boto3, urllib, VPC endpoint clients
- **Authentication**: Cross-account IAM role via VPC endpoints
- **Monitoring**: Dedicated CloudWatch logs and metrics

#### 3. Network Architecture

##### Internet Routing (Current)
```
Internet Lambda → Internet → Commercial AWS → Bedrock
```

##### VPN Routing (New)
```
VPN Lambda → VPC → VPN Gateway → Commercial VPC → Bedrock VPC Endpoint
```

## Components and Interfaces

### 1. API Gateway Resources

#### Resource Structure
```
/v1
├── /bedrock
│   └── /invoke-model (POST) → Internet Lambda
└── /vpn
    └── /bedrock
        └── /invoke-model (POST) → VPN Lambda
```

#### Request/Response Format
Both endpoints use identical request/response formats:

**Request:**
```json
{
  "model_id": "anthropic.claude-3-sonnet-20240229-v1:0",
  "prompt": "Your prompt here",
  "max_tokens": 1000,
  "temperature": 0.7
}
```

**Response:**
```json
{
  "response": "Generated response",
  "model_id": "anthropic.claude-3-sonnet-20240229-v1:0",
  "usage": {
    "input_tokens": 10,
    "output_tokens": 50
  },
  "routing_method": "internet|vpn"
}
```

### 2. Lambda Function Interfaces

#### Internet Lambda Function
```python
def lambda_handler(event, context):
    """Handle internet-routed Bedrock requests"""
    # Parse API Gateway event
    # Authenticate request
    # Route to Commercial Bedrock via internet
    # Return formatted response
```

#### VPN Lambda Function
```python
def lambda_handler(event, context):
    """Handle VPN-routed Bedrock requests"""
    # Parse API Gateway event
    # Authenticate via VPC endpoints
    # Route to Commercial Bedrock via VPN
    # Return formatted response
```

### 3. VPC Configuration

#### VPC Components
- **VPC**: Dedicated VPC for VPN Lambda
- **Private Subnets**: Multi-AZ for high availability
- **VPN Gateway**: Site-to-site VPN to Commercial AWS
- **VPC Endpoints**: For AWS services (Secrets Manager, CloudWatch)
- **Security Groups**: Restrictive rules for VPN traffic only

#### VPC Endpoints Required
- **Secrets Manager**: For credential retrieval
- **CloudWatch Logs**: For logging
- **CloudWatch Metrics**: For monitoring
- **Lambda**: For function execution

## Data Models

### 1. Request Processing Model

```python
class BedrockRequest:
    def __init__(self, event):
        self.model_id = event.get('model_id')
        self.prompt = event.get('prompt')
        self.max_tokens = event.get('max_tokens', 1000)
        self.temperature = event.get('temperature', 0.7)
        self.routing_method = self.detect_routing_method(event)
    
    def detect_routing_method(self, event):
        """Detect routing method from API Gateway path"""
        path = event.get('requestContext', {}).get('path', '')
        return 'vpn' if '/vpn/' in path else 'internet'
```

### 2. Response Model

```python
class BedrockResponse:
    def __init__(self, response_text, model_id, usage, routing_method):
        self.response = response_text
        self.model_id = model_id
        self.usage = usage
        self.routing_method = routing_method
        self.timestamp = datetime.utcnow().isoformat()
    
    def to_api_gateway_response(self):
        """Format for API Gateway return"""
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Routing-Method': self.routing_method
            },
            'body': json.dumps({
                'response': self.response,
                'model_id': self.model_id,
                'usage': self.usage,
                'routing_method': self.routing_method
            })
        }
```

### 3. Configuration Model

```python
class RoutingConfig:
    def __init__(self, routing_method):
        self.routing_method = routing_method
        self.bedrock_endpoint = self.get_bedrock_endpoint()
        self.credentials = self.get_credentials()
        self.timeout = self.get_timeout()
    
    def get_bedrock_endpoint(self):
        if self.routing_method == 'vpn':
            return os.environ['VPN_BEDROCK_ENDPOINT']
        else:
            return 'https://bedrock-runtime.us-east-1.amazonaws.com'
```

## Error Handling

### 1. Error Categories

#### Network Errors
- **Internet Routing**: DNS resolution, connection timeouts, SSL errors
- **VPN Routing**: VPN tunnel down, VPC endpoint unavailable, routing failures

#### Authentication Errors
- **API Key**: Invalid or expired keys
- **IAM Role**: Insufficient permissions, assume role failures
- **Cross-Account**: Trust relationship issues

#### Service Errors
- **Bedrock**: Model not available, quota exceeded, invalid parameters
- **Lambda**: Timeout, memory limit, cold start issues

### 2. Error Response Format

```python
class ErrorResponse:
    def __init__(self, error_code, message, routing_method, details=None):
        self.error_code = error_code
        self.message = message
        self.routing_method = routing_method
        self.details = details or {}
        self.timestamp = datetime.utcnow().isoformat()
    
    def to_api_gateway_response(self):
        status_code = self.get_http_status_code()
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'X-Routing-Method': self.routing_method
            },
            'body': json.dumps({
                'error': {
                    'code': self.error_code,
                    'message': self.message,
                    'routing_method': self.routing_method,
                    'details': self.details,
                    'timestamp': self.timestamp
                }
            })
        }
```

### 3. Error Handling Strategy

#### Retry Logic
- **Network Errors**: Exponential backoff with jitter
- **Rate Limiting**: Respect retry-after headers
- **Transient Errors**: Up to 3 retries with increasing delays

#### Fallback Behavior
- **No Cross-Routing**: VPN failures do not fall back to internet
- **Clear Error Messages**: Indicate which routing method failed
- **Monitoring Integration**: All errors logged and monitored

## Testing Strategy

### 1. Unit Testing

#### Internet Lambda Tests
```python
def test_internet_routing_success():
    """Test successful internet routing"""
    
def test_internet_routing_authentication_failure():
    """Test authentication failure handling"""
    
def test_internet_routing_network_error():
    """Test network error handling"""
```

#### VPN Lambda Tests
```python
def test_vpn_routing_success():
    """Test successful VPN routing"""
    
def test_vpn_routing_tunnel_down():
    """Test VPN tunnel failure handling"""
    
def test_vpn_routing_vpc_endpoint_failure():
    """Test VPC endpoint failure handling"""
```

### 2. Integration Testing

#### API Gateway Integration
```python
def test_api_gateway_internet_path():
    """Test /v1/bedrock/invoke-model path"""
    
def test_api_gateway_vpn_path():
    """Test /v1/vpn/bedrock/invoke-model path"""
    
def test_api_gateway_authentication():
    """Test authentication across both paths"""
```

#### End-to-End Testing
```python
def test_e2e_internet_routing():
    """Test complete internet routing flow"""
    
def test_e2e_vpn_routing():
    """Test complete VPN routing flow"""
    
def test_routing_comparison():
    """Compare responses from both routing methods"""
```

### 3. Performance Testing

#### Load Testing
- **Concurrent Requests**: Test both paths under load
- **Scaling Behavior**: Validate independent scaling
- **Resource Utilization**: Monitor Lambda memory and CPU usage

#### Latency Testing
- **Response Times**: Compare internet vs VPN latency
- **Cold Start Impact**: Measure cold start times for both functions
- **Network Overhead**: Quantify VPN routing overhead

### 4. Security Testing

#### Authentication Testing
- **API Key Validation**: Test key validation on both paths
- **IAM Role Testing**: Validate cross-account role assumptions
- **Unauthorized Access**: Test rejection of invalid credentials

#### Network Security Testing
- **Traffic Analysis**: Verify VPN traffic isolation
- **Endpoint Security**: Test VPC endpoint access controls
- **Data Encryption**: Validate end-to-end encryption

## Deployment Strategy

### 1. Phased Deployment

#### Phase 1: Infrastructure Setup
1. Deploy VPC and VPN infrastructure
2. Create VPC endpoints
3. Set up monitoring and logging

#### Phase 2: VPN Lambda Deployment
1. Deploy VPN Lambda function in VPC
2. Configure environment variables and permissions
3. Test VPN routing independently

#### Phase 3: API Gateway Integration
1. Add VPN path to existing API Gateway
2. Configure integration with VPN Lambda
3. Test both paths end-to-end

#### Phase 4: Monitoring and Validation
1. Set up separate dashboards for each routing method
2. Configure alerts and notifications
3. Validate performance and reliability

### 2. Rollback Strategy

#### Immediate Rollback
- **Remove VPN Path**: Delete API Gateway VPN resource
- **Preserve Internet Path**: Ensure no impact to existing functionality
- **Clean Rollback**: Remove VPN Lambda and VPC resources if needed

#### Gradual Rollback
- **Disable VPN Path**: Return 503 for VPN requests
- **Monitor Impact**: Ensure no client disruption
- **Complete Removal**: Remove resources after validation period

This design provides a robust, scalable solution for dual routing while maintaining clear separation of concerns and enabling independent operation of both routing methods.