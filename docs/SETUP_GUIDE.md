# Setup Guide: Cross-Partition Bedrock Inference

This guide walks you through setting up the Cross-Partition Bedrock Inference system from deployment to testing.

## 🚀 Quick Setup (Recommended)

### 1. Deploy the Infrastructure

```bash
# Clone the repository
git clone https://github.com/freshie/bedrock-cross-partition-inferencing.git
cd bedrock-cross-partition-inferencing

# Deploy to your AWS environment (internet routing)
./scripts/deploy-over-internet.sh
```

### 2. Extract Configuration

After deployment, extract your API endpoints automatically:

```bash
# This creates config/config.sh with your actual endpoints
./scripts/get-config.sh
```

### 3. Test the System

```bash
# Test basic functionality
./test-invoke-model.sh

# Test Claude 4.1 specifically
./test-claude-4-1.sh

# Run comprehensive tests
./test-cross-partition.sh
```

## 🔧 Manual Configuration

If you prefer to configure manually or need custom settings:

### 1. Copy Configuration Template

```bash
cp config/config.example.sh config/config.sh
```

### 2. Update Configuration

Edit `config/config.sh` with your values:

```bash
# Your API Gateway base URL (get from CloudFormation outputs)
export API_BASE_URL="https://your-api-id.execute-api.your-region.amazonaws.com/v1"

# AWS Configuration
export AWS_REGION="us-east-1"
export AWS_PROFILE="your-profile-name"

# Stack name
export STACK_NAME="cross-partition-bedrock-inference"
```

### 3. Get Your API Gateway URL

From AWS Console:
1. Go to CloudFormation
2. Find your stack (default: `cross-partition-inference-mvp`)
3. Go to Outputs tab
4. Copy the `ApiGatewayUrl` value

Or use AWS CLI:
```bash
aws cloudformation describe-stacks \
  --stack-name cross-partition-inference-mvp \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayUrl`].OutputValue' \
  --output text
```

## 🔐 Security Configuration

### Bedrock API Key Setup

1. **Create Commercial AWS Bedrock API Key**
   - Follow the guide: [docs/create-comprehensive-bedrock-api-key.md](create-comprehensive-bedrock-api-key.md)

2. **Update Secrets Manager**
   ```bash
   # Replace with your actual base64-encoded API key
   aws secretsmanager update-secret \
     --secret-id cross-partition-commercial-creds \
     --secret-string '{"bedrock_api_key":"YOUR_BASE64_KEY","region":"us-east-1"}'
   ```

## 📁 Configuration Files

### config/config.sh (Git-ignored)
Your actual configuration with real endpoints and credentials.

```bash
#!/bin/bash
export API_BASE_URL="https://abc123.execute-api.us-east-1.amazonaws.com/v1"
export AWS_REGION="us-east-1"
export AWS_PROFILE="govcloud"
# ... other settings
```

### config.example.sh (Version controlled)
Template with placeholder values and documentation.

## 🧪 Testing Your Setup

### Basic Connectivity Test
```bash
source config/config.sh
curl -X GET "$API_BASE_URL/bedrock/models"
```

### Full Integration Test
```bash
./test-invoke-model.sh
```

### Specific Model Tests
```bash
# Test Claude 4.1
./test-claude-4-1.sh

# Test with mock credentials (for validation)
./test-with-mock-key.sh
```

## 🔍 Troubleshooting

### Configuration Issues

**Problem**: `config.sh not found`
```bash
# Solution: Extract from CloudFormation
./scripts/get-config.sh

# Or copy template
cp config/config.example.sh config/config.sh
# Edit config/config.sh with your values
```

**Problem**: `API_BASE_URL not set`
```bash
# Check your config/config.sh file
cat config/config.sh

# Ensure you're sourcing it
source config/config.sh
echo $API_BASE_URL
```

### API Endpoint Issues

**Problem**: Wrong API Gateway URL
```bash
# Re-extract from CloudFormation
./scripts/get-config.sh

# Or check CloudFormation outputs
aws cloudformation describe-stacks \
  --stack-name your-stack-name \
  --query 'Stacks[0].Outputs'
```

### Authentication Issues

**Problem**: 403 Forbidden errors
- Check your AWS profile has correct permissions
- Verify you're using the right AWS region
- Ensure your Bedrock API key is valid

**Problem**: 500 Internal Server Error
- Check CloudWatch logs for the Lambda function
- Verify Secrets Manager has the correct Bedrock API key
- Test with mock credentials first: `./test-with-mock-key.sh`

## 📋 Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `API_BASE_URL` | API Gateway base URL | `https://abc123.execute-api.us-east-1.amazonaws.com/v1` |
| `AWS_REGION` | AWS region for deployment | `us-east-1` |
| `AWS_PROFILE` | AWS CLI profile to use | `govcloud` |
| `STACK_NAME` | CloudFormation stack name | `cross-partition-inference-mvp` |
| `BEDROCK_SECRET_NAME` | Secrets Manager secret name | `cross-partition-commercial-creds` |
| `TEST_MODEL_ID` | Default model for testing | `anthropic.claude-3-5-sonnet-20241022-v2:0` |

## 🎯 Next Steps

1. **Deploy**: Use `./scripts/deploy-over-internet.sh` for internet-based deployment or `./scripts/deploy-complete-vpn-infrastructure.sh` for VPN-based deployment
2. **Configure**: Run `./scripts/get-config.sh` to extract endpoints
3. **Secure**: Set up real Bedrock API keys in Secrets Manager
4. **Test**: Run `./test-invoke-model.sh` to verify functionality
5. **Monitor**: Check CloudWatch logs and DynamoDB for request tracking

## 📚 Additional Resources

- [Architecture Overview](../ARCHITECTURE.md)
- [API Key Creation Guide](create-comprehensive-bedrock-api-key.md)
- [AWS Profile Setup](aws-profile-guide.md)
- [Technical Summary](TECHNICAL_SUMMARY.md)