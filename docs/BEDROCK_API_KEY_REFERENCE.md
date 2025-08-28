# Bedrock API Key Reference

## ⚠️ SECURITY NOTICE ⚠️

**This file previously contained exposed AWS credentials that have been removed and revoked.**

## API Key Management

**Location**: AWS Secrets Manager in GovCloud partition
- Secret Name: `cross-partition-commercial-creds`
- Field: `bedrock_api_key`

**Key Details**:
- User: bedrock-cross-partition-user
- Region: us-east-1
- Permissions: AmazonBedrockFullAccess + BedrockCrossPartitionFullAccess
- Rotation: Every 6 months

## Security Best Practices

### ❌ NEVER DO:
- Store actual API keys in code or documentation
- Commit credentials to version control
- Share credentials in plain text

### ✅ ALWAYS DO:
- Store credentials in AWS Secrets Manager
- Use IAM roles when possible
- Rotate credentials regularly
- Monitor for exposed credentials

## Setup Instructions

1. **Create Bedrock API Key** (see docs/create-comprehensive-bedrock-api-key.md)
2. **Store in Secrets Manager**:
   ```bash
   aws secretsmanager update-secret \
     --secret-id cross-partition-commercial-creds \
     --secret-string '{"bedrock_api_key":"YOUR_BASE64_KEY","region":"us-east-1"}'
   ```
3. **Test connectivity** using provided test scripts

## Credential Rotation

Set calendar reminders to rotate credentials every 6 months:
- Create new API key
- Update Secrets Manager
- Test functionality
- Revoke old key