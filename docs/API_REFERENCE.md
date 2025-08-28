# API Reference

Complete API documentation for the Cross-Partition Bedrock Inference system.

## 🚀 Base Configuration

After deployment, get your API endpoints:
```bash
# Extract endpoints from CloudFormation
./scripts/get-config.sh

# Source the configuration
source config/config.sh
echo $API_BASE_URL
```

## 🔑 Authentication

All API calls require bearer token authentication:

```bash
# Header format
Authorization: Bearer YOUR_BEARER_TOKEN
```

The bearer token is stored in AWS Secrets Manager and can be updated:
```bash
./scripts/update-bearer-token-secret.sh
```

## 📡 API Endpoints

### 1. Invoke Model Endpoint

**Endpoint:** `POST /bedrock/invoke-model`

**Purpose:** Invoke any Bedrock model with cross-partition routing

**Request Format:**
```json
{
  "modelId": "anthropic.claude-3-5-sonnet-20241022-v2:0",
  "body": {
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 1000,
    "messages": [
      {
        "role": "user",
        "content": "Hello, how are you?"
      }
    ]
  }
}
```

**Response Format:**
```json
{
  "statusCode": 200,
  "body": {
    "content": [
      {
        "text": "Hello! I'm doing well, thank you for asking...",
        "type": "text"
      }
    ],
    "id": "msg_01ABC123",
    "model": "claude-3-5-sonnet-20241022",
    "role": "assistant",
    "stop_reason": "end_turn",
    "stop_sequence": null,
    "type": "message",
    "usage": {
      "input_tokens": 12,
      "output_tokens": 25
    }
  }
}
```

### 2. List Models Endpoint

**Endpoint:** `GET /bedrock/models`

**Purpose:** List available Bedrock models

**Response Format:**
```json
{
  "statusCode": 200,
  "models": [
    {
      "modelId": "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "modelName": "Claude 3.5 Sonnet",
      "providerName": "Anthropic",
      "inputModalities": ["TEXT"],
      "outputModalities": ["TEXT"],
      "responseStreamingSupported": true
    }
  ]
}
```

### 3. Health Check Endpoint

**Endpoint:** `GET /health`

**Purpose:** Check system health and connectivity

**Response Format:**
```json
{
  "statusCode": 200,
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "1.3.2",
  "connectivity": {
    "commercial_partition": "connected",
    "secrets_manager": "accessible",
    "dynamodb": "accessible"
  }
}
```

## 🤖 Supported Models

### Anthropic Models
- `anthropic.claude-3-5-sonnet-20241022-v2:0` - Claude 3.5 Sonnet
- `anthropic.claude-3-haiku-20240307-v1:0` - Claude 3 Haiku
- `anthropic.claude-v2:1` - Claude 2.1

### Amazon Models
- `amazon.nova-premier-v1:0` - Nova Premier
- `amazon.nova-lite-v1:0` - Nova Lite
- `amazon.nova-micro-v1:0` - Nova Micro

### Meta Models
- `meta.llama3-2-90b-instruct-v1:0` - Llama 3.2 90B
- `meta.llama3-2-11b-instruct-v1:0` - Llama 3.2 11B
- `meta.llama3-2-3b-instruct-v1:0` - Llama 3.2 3B

## 📝 Request Examples

### cURL Examples

```bash
# First extract your endpoint
./scripts/get-config.sh
source config/config.sh

# Invoke Claude 3.5 Sonnet
curl -X POST "$API_BASE_URL/bedrock/invoke-model" \
  -H "Authorization: Bearer YOUR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "modelId": "anthropic.claude-3-5-sonnet-20241022-v2:0",
    "body": {
      "anthropic_version": "bedrock-2023-05-31",
      "max_tokens": 1000,
      "messages": [
        {
          "role": "user",
          "content": "Explain quantum computing in simple terms"
        }
      ]
    }
  }'

# List available models
curl -X GET "$API_BASE_URL/bedrock/models" \
  -H "Authorization: Bearer YOUR_BEARER_TOKEN"

# Health check
curl -X GET "$API_BASE_URL/health" \
  -H "Authorization: Bearer YOUR_BEARER_TOKEN"
```

### Python Examples

```python
import requests
import json
import os

# Load configuration
# First run: ./scripts/get-config.sh to extract from CloudFormation
# Or copy config/config.example.sh to config/config.sh and update manually
import os
api_base_url = os.environ.get('API_BASE_URL')
bearer_token = 'your-bearer-token'

headers = {
    'Authorization': f'Bearer {bearer_token}',
    'Content-Type': 'application/json'
}

# Invoke Claude 3.5 Sonnet
payload = {
    "modelId": "anthropic.claude-3-5-sonnet-20241022-v2:0",
    "body": {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1000,
        "messages": [
            {
                "role": "user",
                "content": "Write a Python function to calculate fibonacci numbers"
            }
        ]
    }
}

response = requests.post(
    f"{api_base_url}/bedrock/invoke-model",
    headers=headers,
    json=payload
)

print(json.dumps(response.json(), indent=2))
```

### JavaScript Examples

```javascript
// Node.js example
const axios = require('axios');

const apiBaseUrl = process.env.API_BASE_URL;
const bearerToken = 'your-bearer-token';

const headers = {
    'Authorization': `Bearer ${bearerToken}`,
    'Content-Type': 'application/json'
};

// Invoke Nova Premier
const payload = {
    modelId: 'amazon.nova-premier-v1:0',
    body: {
        messages: [
            {
                role: 'user',
                content: [
                    {
                        text: 'Analyze this business proposal and provide recommendations'
                    }
                ]
            }
        ],
        inferenceConfig: {
            max_new_tokens: 1000,
            temperature: 0.7
        }
    }
};

axios.post(`${apiBaseUrl}/bedrock/invoke-model`, payload, { headers })
    .then(response => {
        console.log(JSON.stringify(response.data, null, 2));
    })
    .catch(error => {
        console.error('Error:', error.response?.data || error.message);
    });
```

## 🚨 Error Handling

### Common Error Codes

| Status Code | Error Type | Description |
|-------------|------------|-------------|
| 400 | Bad Request | Invalid request format or parameters |
| 401 | Unauthorized | Missing or invalid bearer token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Endpoint or model not found |
| 429 | Rate Limited | Too many requests |
| 500 | Internal Error | Server-side error |
| 502 | Bad Gateway | Upstream service error |
| 503 | Service Unavailable | Service temporarily unavailable |

### Error Response Format

```json
{
  "statusCode": 400,
  "error": {
    "type": "ValidationException",
    "message": "Invalid model ID specified",
    "details": {
      "modelId": "invalid-model-id",
      "availableModels": ["anthropic.claude-3-5-sonnet-20241022-v2:0"]
    }
  },
  "requestId": "abc123-def456-ghi789",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

## 📊 Rate Limits

### Default Limits
- **Requests per minute**: 100
- **Concurrent requests**: 10
- **Token limit per request**: Varies by model

### Model-Specific Limits
- **Claude models**: 100,000 tokens per request
- **Nova models**: 200,000 tokens per request
- **Llama models**: 128,000 tokens per request

## 🔍 Monitoring & Logging

### Request Logging
All requests are logged to DynamoDB with:
- Request ID
- Timestamp
- Model used
- Token usage
- Response time
- User information

### CloudWatch Metrics
- Request count
- Error rate
- Response time
- Token usage
- Cost tracking

### Accessing Logs
```bash
# View recent requests
aws dynamodb scan --table-name CrossPartitionAuditLog --max-items 10

# View CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace "CrossPartition/Bedrock" \
  --metric-name "RequestCount" \
  --start-time 2024-01-15T00:00:00Z \
  --end-time 2024-01-15T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

## 🔧 Configuration

### Environment Variables
Set these in your application:
- `API_BASE_URL` - Your API Gateway endpoint
- `BEARER_TOKEN` - Authentication token
- `AWS_REGION` - AWS region (default: us-east-1)

### Secrets Manager
Update credentials:
```bash
# Update bearer token
./scripts/update-bearer-token-secret.sh

# Update commercial credentials
aws secretsmanager update-secret \
  --secret-id cross-partition-commercial-creds \
  --secret-string '{"bedrock_api_key": "YOUR_KEY", "region": "us-east-1"}'
```