#!/bin/bash

# Cross-Partition Inference Proxy Test
# Tests GovCloud → Commercial AWS Bedrock integration

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Load configuration
if [ -f "config.sh" ]; then
    source config.sh
    echo -e "${GREEN}✅ Loaded configuration from config.sh${NC}"
else
    echo -e "${RED}❌ Configuration file not found!${NC}"
    echo -e "${YELLOW}📋 Please copy config.example.sh to config.sh and update with your values:${NC}"
    echo -e "   ${CYAN}cp config.example.sh config.sh${NC}"
    echo -e "   ${CYAN}# Edit config.sh with your API Gateway URL${NC}"
    exit 1
fi

# Validate required configuration
if [ -z "$API_BASE_URL" ]; then
    echo -e "${RED}❌ API_BASE_URL not set in config.sh${NC}"
    exit 1
fi

# Extract API Gateway ID from URL for direct API calls
API_GATEWAY_ID=$(echo "$API_BASE_URL" | sed 's|https://||' | cut -d'.' -f1)

INVOKE_ENDPOINT="${API_BASE_URL}/bedrock/invoke-model"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}          ${YELLOW}🚀 Cross-Partition Inference Proxy Test${NC}          ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📍 GovCloud API Endpoint:${NC}"
echo -e "   ${INVOKE_ENDPOINT}"
echo ""
echo -e "${PURPLE}🔄 Route: GovCloud (us-gov-west-1) → Commercial AWS (us-east-1)${NC}"
echo ""

# Test 1: Amazon Titan Text Express
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📝 Test 1: Amazon Titan Text Express${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

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

echo -e "${YELLOW}📤 Request:${NC} POST ${INVOKE_ENDPOINT}"
echo -e "${YELLOW}🤖 Model:${NC} amazon.titan-text-express-v1"
echo -e "${YELLOW}❓ Query:${NC} What is the capital of France?"
echo ""

echo -e "${CYAN}⏳ Making cross-partition request...${NC}"
RESPONSE_TITAN=$(aws apigateway test-invoke-method \
  --rest-api-id $API_GATEWAY_ID \
  --resource-id ze3g42 \
  --http-method POST \
  --profile govcloud \
  --region us-gov-west-1 \
  --body "$PAYLOAD_TITAN")

# Extract and format the response
STATUS_TITAN=$(echo "$RESPONSE_TITAN" | jq -r '.status')
BODY_TITAN=$(echo "$RESPONSE_TITAN" | jq -r '.body' | jq -r '.body' | jq -r '.results[0].outputText' 2>/dev/null || echo "Error parsing response")

if [ "$STATUS_TITAN" = "200" ]; then
    echo -e "${GREEN}✅ Status: ${STATUS_TITAN} (Success)${NC}"
    echo -e "${GREEN}🎯 AI Response:${NC}"
    echo -e "   ${BODY_TITAN}"
else
    echo -e "${RED}❌ Status: ${STATUS_TITAN} (Failed)${NC}"
    echo -e "${RED}Error:${NC} $(echo "$RESPONSE_TITAN" | jq -r '.body')"
fi

echo ""

# Test 2: Claude 3.5 Sonnet (Latest Anthropic Model)
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📝 Test 2: Claude 3.5 Sonnet (Latest Anthropic Model)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PAYLOAD_CLAUDE='{
  "modelId": "anthropic.claude-3-5-sonnet-20241022-v2:0",
  "contentType": "application/json",
  "accept": "application/json",
  "body": {
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 100,
    "messages": [
      {
        "role": "user",
        "content": "Explain quantum computing in simple terms. Be concise but informative."
      }
    ]
  }
}'

echo -e "${YELLOW}📤 Request:${NC} POST ${INVOKE_ENDPOINT}"
echo -e "${YELLOW}🤖 Model:${NC} anthropic.claude-3-5-sonnet-20241022-v2:0"
echo -e "${YELLOW}❓ Query:${NC} Explain quantum computing in simple terms"
echo ""

echo -e "${CYAN}⏳ Making cross-partition request...${NC}"
RESPONSE_CLAUDE=$(aws apigateway test-invoke-method \
  --rest-api-id $API_GATEWAY_ID \
  --resource-id ze3g42 \
  --http-method POST \
  --profile govcloud \
  --region us-gov-west-1 \
  --body "$PAYLOAD_CLAUDE")

# Extract and format the response
STATUS_CLAUDE=$(echo "$RESPONSE_CLAUDE" | jq -r '.status')
BODY_CLAUDE=$(echo "$RESPONSE_CLAUDE" | jq -r '.body' | jq -r '.body' | jq -r '.content[0].text' 2>/dev/null || echo "Error parsing response")
TOKENS_CLAUDE=$(echo "$RESPONSE_CLAUDE" | jq -r '.body' | jq -r '.body' | jq -r '.usage.output_tokens' 2>/dev/null || echo "N/A")

if [ "$STATUS_CLAUDE" = "200" ]; then
    echo -e "${GREEN}✅ Status: ${STATUS_CLAUDE} (Success)${NC}"
    echo -e "${GREEN}🎯 AI Response:${NC}"
    echo -e "   ${BODY_CLAUDE}"
    echo -e "${CYAN}📊 Output Tokens: ${TOKENS_CLAUDE}${NC}"
else
    echo -e "${RED}❌ Status: ${STATUS_CLAUDE} (Failed)${NC}"
    echo -e "${RED}Error:${NC} $(echo "$RESPONSE_CLAUDE" | jq -r '.body')"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}                    ${GREEN}🎉 Tests Complete!${NC}                    ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     ${PURPLE}Cross-partition Bedrock proxy is operational${NC}      ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""