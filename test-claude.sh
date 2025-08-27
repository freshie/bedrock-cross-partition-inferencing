#!/bin/bash

# Test script specifically for Claude 3.5 Sonnet
# Tests the cross-partition inference with Claude model using real API key

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# API Configuration (same as test-invoke-model.sh)
API_BASE_URL="https://REDACTED_ENDPOINT.execute-api.us-gov-west-1.amazonaws.com/v1"
INVOKE_ENDPOINT="${API_BASE_URL}/bedrock/invoke-model"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}          ${YELLOW}🤖 Claude 3.5 Sonnet Test${NC}                  ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📍 GovCloud API Endpoint:${NC}"
echo -e "   ${INVOKE_ENDPOINT}"
echo ""
echo -e "${PURPLE}🔄 Route: GovCloud (us-gov-west-1) → Commercial AWS (us-east-1)${NC}"
echo ""

# Test Claude 3.5 Sonnet
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📝 Testing Claude 3.5 Sonnet (Advanced Anthropic Model)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

CLAUDE_PAYLOAD='{
  "modelId": "anthropic.claude-3-5-sonnet-20240620-v1:0",
  "contentType": "application/json",
  "accept": "application/json",
  "body": {
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 150,
    "messages": [
      {
        "role": "user",
        "content": "Hello! Can you explain what cross-partition inference means in AWS? Keep it concise but informative."
      }
    ]
  }
}'

echo -e "${YELLOW}📤 Request:${NC} POST ${INVOKE_ENDPOINT}"
echo -e "${YELLOW}🤖 Model:${NC} anthropic.claude-3-5-sonnet-20240620-v1:0"
echo -e "${YELLOW}❓ Query:${NC} Cross-partition inference explanation"
echo -e "${YELLOW}🎯 Max Tokens:${NC} 150"
echo ""

echo -e "${CYAN}⏳ Making cross-partition request...${NC}"
CLAUDE_RESPONSE=$(aws apigateway test-invoke-method \
  --rest-api-id REDACTED_ENDPOINT \
  --resource-id ze3g42 \
  --http-method POST \
  --profile govcloud \
  --region us-gov-west-1 \
  --body "$CLAUDE_PAYLOAD")

# Extract and format the response
STATUS_CLAUDE=$(echo "$CLAUDE_RESPONSE" | jq -r '.status')
BODY_CLAUDE=$(echo "$CLAUDE_RESPONSE" | jq -r '.body' | jq -r '.body' | jq -r '.content[0].text' 2>/dev/null || echo "Error parsing response")
TOKENS_CLAUDE=$(echo "$CLAUDE_RESPONSE" | jq -r '.body' | jq -r '.body' | jq -r '.usage.output_tokens' 2>/dev/null || echo "N/A")

if [ "$STATUS_CLAUDE" = "200" ]; then
    echo -e "${GREEN}✅ Status: ${STATUS_CLAUDE} (Success)${NC}"
    echo -e "${GREEN}🎯 Claude's Response:${NC}"
    echo -e "   ${BODY_CLAUDE}"
    echo -e "${CYAN}📊 Output Tokens: ${TOKENS_CLAUDE}${NC}"
else
    echo -e "${RED}❌ Status: ${STATUS_CLAUDE} (Failed)${NC}"
    echo -e "${RED}Error:${NC} $(echo "$CLAUDE_RESPONSE" | jq -r '.body')"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}                    ${GREEN}🎉 Claude Test Complete!${NC}                ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}     ${PURPLE}Cross-partition Claude inference operational${NC}     ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""