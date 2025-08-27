#!/bin/bash

# Test script specifically for Claude Opus 4.1
# Tests the cross-partition inference with Claude 4.1 using inference profiles

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
echo -e "${BLUE}║${NC}          ${YELLOW}🚀 Claude Opus 4.1 Test${NC}                     ${BLUE}║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📍 GovCloud API Endpoint:${NC}"
echo -e "   ${INVOKE_ENDPOINT}"
echo ""
echo -e "${PURPLE}🔄 Route: GovCloud (us-gov-west-1) → Commercial AWS (us-east-1)${NC}"
echo ""

# Test Claude Opus 4.1
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📝 Testing Claude Opus 4.1 (Most Advanced Anthropic Model)${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

CLAUDE_41_PAYLOAD='{
  "modelId": "us.anthropic.claude-opus-4-1-20250805-v1:0",
  "contentType": "application/json",
  "accept": "application/json",
  "body": {
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 200,
    "messages": [
      {
        "role": "user",
        "content": "Hello Claude 4.1! Can you explain the key advantages of cross-partition AI inference in government cloud environments? Please be detailed but concise."
      }
    ]
  }
}'

echo -e "${YELLOW}📤 Request:${NC} POST ${INVOKE_ENDPOINT}"
echo -e "${YELLOW}🤖 Model:${NC} us.anthropic.claude-opus-4-1-20250805-v1:0 (Claude Opus 4.1 via inference profile)"
echo -e "${YELLOW}❓ Query:${NC} Cross-partition AI inference advantages"
echo -e "${YELLOW}🎯 Max Tokens:${NC} 200"
echo ""

echo -e "${CYAN}⏳ Making cross-partition request with inference profile support...${NC}"
CLAUDE_41_RESPONSE=$(aws apigateway test-invoke-method \
  --rest-api-id REDACTED_ENDPOINT \
  --resource-id ze3g42 \
  --http-method POST \
  --profile govcloud \
  --region us-gov-west-1 \
  --body "$CLAUDE_41_PAYLOAD")

# Extract and format the response
STATUS_CLAUDE_41=$(echo "$CLAUDE_41_RESPONSE" | jq -r '.status')
BODY_CLAUDE_41=$(echo "$CLAUDE_41_RESPONSE" | jq -r '.body' | jq -r '.body' | jq -r '.content[0].text' 2>/dev/null || echo "Error parsing response")
TOKENS_CLAUDE_41=$(echo "$CLAUDE_41_RESPONSE" | jq -r '.body' | jq -r '.body' | jq -r '.usage.output_tokens' 2>/dev/null || echo "N/A")

if [ "$STATUS_CLAUDE_41" = "200" ]; then
    echo -e "${GREEN}✅ Status: ${STATUS_CLAUDE_41} (Success)${NC}"
    echo -e "${GREEN}🎯 Claude 4.1's Response:${NC}"
    echo -e "   ${BODY_CLAUDE_41}"
    echo -e "${CYAN}📊 Output Tokens: ${TOKENS_CLAUDE_41}${NC}"
else
    echo -e "${RED}❌ Status: ${STATUS_CLAUDE_41} (Failed)${NC}"
    echo -e "${RED}Error:${NC} $(echo "$CLAUDE_41_RESPONSE" | jq -r '.body')"
    
    # Show additional debug info
    echo ""
    echo -e "${YELLOW}🔍 Debug Information:${NC}"
    echo "$CLAUDE_41_RESPONSE" | jq '.' 2>/dev/null || echo "$CLAUDE_41_RESPONSE"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}                    ${GREEN}🎉 Claude 4.1 Test Complete!${NC}           ${BLUE}║${NC}"
if [ "$STATUS_CLAUDE_41" = "200" ]; then
    echo -e "${BLUE}║${NC}     ${PURPLE}Claude Opus 4.1 cross-partition inference working!${NC}  ${BLUE}║${NC}"
else
    echo -e "${BLUE}║${NC}     ${YELLOW}Claude 4.1 inference failed - check logs${NC}           ${BLUE}║${NC}"
fi
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""