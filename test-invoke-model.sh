#!/bin/bash

# Test script for the Bedrock invoke-model endpoint
# This tests the cross-partition inference proxy

set -e

API_BASE_URL="https://REDACTED_ENDPOINT.execute-api.us-gov-west-1.amazonaws.com/v1"
INVOKE_ENDPOINT="${API_BASE_URL}/bedrock/invoke-model"

echo "🧪 Testing Bedrock Invoke Model Endpoint"
echo "========================================"
echo "Endpoint: ${INVOKE_ENDPOINT}"
echo ""

# Test 1: Simple text generation with Claude
echo "📝 Test 1: Text generation with Claude 3.5 Sonnet"
echo "---------------------------------------------------"

PAYLOAD='{
  "modelId": "anthropic.claude-3-5-sonnet-20240620-v1:0",
  "contentType": "application/json",
  "accept": "application/json",
  "body": {
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 100,
    "messages": [
      {
        "role": "user",
        "content": "Hello! Can you tell me a short joke?"
      }
    ]
  }
}'

echo "Request payload:"
echo "$PAYLOAD" | jq .
echo ""

echo "Making request..."
RESPONSE=$(curl -s -X POST "$INVOKE_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

echo "Response:"
echo "$RESPONSE" | jq .
echo ""

# Test 2: Simple text generation with Amazon Nova
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

echo "Making request..."
RESPONSE_NOVA=$(curl -s -X POST "$INVOKE_ENDPOINT" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD_NOVA")

echo "Response:"
echo "$RESPONSE_NOVA" | jq .
echo ""

echo "✅ Invoke model endpoint tests completed!"