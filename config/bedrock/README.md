# Bedrock Configuration Files

This directory contains configuration files and policies for setting up Amazon Bedrock access for cross-partition inference.

## Files

### `bedrock-api-key-config.json`
Example configuration showing the structure of a Bedrock service credential. This file contains:
- Service credential details (user name, ID, alias)
- Base64-encoded Bedrock API key
- Associated IAM policies
- Expiration information

**⚠️ Security Note**: This is an example file. In production, never store actual API keys in configuration files. Use AWS Secrets Manager instead.

### `bedrock-full-access-policy.json`
IAM policy document that grants comprehensive access to Amazon Bedrock services, including:
- Foundation model access and listing
- Model inference capabilities
- Inference profile management
- Knowledge base operations
- Conversation API access

## Usage

### Setting Up Bedrock API Key
1. Create a Bedrock service credential in AWS Commercial partition
2. Store the credential securely in AWS Secrets Manager
3. Use the policy document to configure appropriate permissions

### For Development
```bash
# Update Secrets Manager with your actual Bedrock API key
aws secretsmanager update-secret \
  --secret-id cross-partition-commercial-creds \
  --secret-string '{
    "bedrock_api_key": "YOUR_BASE64_ENCODED_KEY",
    "region": "us-east-1"
  }'
```

### For Production
- Never use the example configuration directly
- Always use AWS Secrets Manager for credential storage
- Implement proper IAM role-based access
- Enable CloudTrail logging for audit compliance

## Related Documentation
- [Bedrock API Key Setup Guide](../../docs/create-comprehensive-bedrock-api-key.md)
- [Security Best Practices](../../docs/security-checklist.md)
- [Setup Guide](../../docs/SETUP_GUIDE.md)