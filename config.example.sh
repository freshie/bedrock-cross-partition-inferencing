#!/bin/bash

# Cross-Partition Bedrock Inference Configuration
# Copy this file to config.sh and update with your actual values
# config.sh is git-ignored for security

# =============================================================================
# API Gateway Configuration
# =============================================================================

# Your API Gateway base URL (without /v1 suffix)
# Example: https://abc123def4.execute-api.us-east-1.amazonaws.com
# Get this from your CloudFormation stack outputs after deployment
export API_BASE_URL="https://your-api-id.execute-api.your-region.amazonaws.com/v1"

# =============================================================================
# AWS Configuration
# =============================================================================

# AWS Region where your infrastructure is deployed
export AWS_REGION="us-east-1"

# AWS Profile to use (optional, defaults to default profile)
# export AWS_PROFILE="your-profile-name"

# =============================================================================
# Testing Configuration
# =============================================================================

# Model ID to use for testing (optional, has sensible defaults)
# export TEST_MODEL_ID="anthropic.claude-3-5-sonnet-20241022-v2:0"

# Maximum tokens for test requests
# export TEST_MAX_TOKENS="1000"

# =============================================================================
# Deployment Configuration
# =============================================================================

# CloudFormation stack name
export STACK_NAME="cross-partition-bedrock-inference"

# =============================================================================
# Security Configuration
# =============================================================================

# Secrets Manager secret name for Bedrock credentials
export BEDROCK_SECRET_NAME="bedrock-cross-partition-credentials"

# =============================================================================
# Instructions
# =============================================================================
# 1. Copy this file: cp config.example.sh config.sh
# 2. Update the values above with your actual configuration
# 3. Source the config: source config.sh
# 4. Run your tests: ./test-invoke-model.sh