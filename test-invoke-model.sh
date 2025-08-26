#!/bin/bash

# Test script for the Bedrock invoke-model endpoint using AWS CLI
# This tests the cross-partition inference proxy with proper authentication

set -e

echo "🧪 Testing Bedrock Invoke Model Endpoint"
echo "========================================"
echo "Using AWS CLI test-invoke-method for authentication"
echo ""

# Test 1: Simple text generation with Titan Text Express (should be available)
echo "📝 Test 1: Text generation with Titan Text Express"
echo "-------------------------------------------------"

PAYLOAD_TITAN='{
  "modelId": "amazon.titan-text-express-v1",
  "contentType": "application/json",
  "accept": "application/json",
  "body": {
    "inputText": "What is the capital of France? Please answer in one sentence.",
    "textGenerationConfig": {
      "maxTokenCount": 50,
      "temperature": 0.7
    }
  }
}'

echo "Request payload:"
echo "$PAYLOAD_TITAN" | jq .
echo ""

echo "Making request via AWS CLI..."
RESPONSE_TITAN=$(aws apigateway test-invoke-method \
  --rest-api-id REDACTED_ENDPOINT \
  --resource-id ze3g42 \
  --http-method POST \
  --profile govcloud \
  --region us-gov-west-1 \
  --body "$PAYLOAD_TITAN")

echo "Response:"
echo "$RESPONSE_TITAN" | jq .
echo ""

# Test 2: Simple text generation with Amazon Nova Micro
echo "📝 Test 2: Text generation with Amazon Nova Micro"
echo "------------------------------------------------"

PAYLOAD_NOVA='{
  "modelId": "amazon.nova-micro-v1:0",
  "contentType": "application/json",
  "accept": "application/json",
  "body": {
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "text": "What is the capital of France?"
          }
        ]
      }
    ],
    "inferenceConfig": {
      "maxTokens": 50,
      "temperature": 0.7
    }
  }
}'

echo "Request payload:"
echo "$PAYLOAD_NOVA" | jq .
echo ""

echo "Making request via AWS CLI..."
RESPONSE_NOVA=$(aws apigateway test-invoke-method \
  --rest-api-id REDACTED_ENDPOINT \
  --resource-id ze3g42 \
  --http-method POST \
  --profile govcloud \
  --region us-gov-west-1 \
  --body "$PAYLOAD_NOVA")

echo "Response:"
echo "$RESPONSE_NOVA" | jq .
echo ""

echo "✅ Invoke model endpoint tests completed!"