# Create Real Amazon Bedrock API Key

## Overview

This guide will help you create a real Amazon Bedrock API key in your commercial AWS account that can be used for cross-partition inference from GovCloud.

## Prerequisites

- Commercial AWS account with Bedrock access
- AWS CLI configured for commercial account
- Permissions to create IAM users and policies

## Step 1: Create IAM User for Bedrock

```bash
# Create IAM user for Bedrock API access
aws iam create-user --user-name bedrock-cross-partition-user

# Attach the basic Bedrock policy
aws iam attach-user-policy \
    --user-name bedrock-cross-partition-user \
    --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess
```

## Step 2: Create Custom Policy for Enhanced Permissions

Create a custom policy that includes inference profile management:

```bash
# Create the policy document
cat > bedrock-enhanced-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream",
                "bedrock:ListFoundationModels",
                "bedrock:GetFoundationModel",
                "bedrock:CreateInferenceProfile",
                "bedrock:GetInferenceProfile",
                "bedrock:ListInferenceProfiles",
                "bedrock:DeleteInferenceProfile",
                "bedrock:TagResource",
                "bedrock:UntagResource",
                "bedrock:ListTagsForResource"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the policy
aws iam create-policy \
    --policy-name BedrockCrossPartitionEnhanced \
    --policy-document file://bedrock-enhanced-policy.json

# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Attach the custom policy
aws iam attach-user-policy \
    --user-name bedrock-cross-partition-user \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/BedrockCrossPartitionEnhanced
```

## Step 3: Generate Bedrock API Key

```bash
# Generate the Bedrock API key (valid for 6 months = 180 days)
aws iam create-service-specific-credential \
    --user-name bedrock-cross-partition-user \
    --service-name bedrock.amazonaws.com \
    --credential-age-days 180
```

This will return output like:
```json
{
    "ServiceSpecificCredential": {
        "CreateDate": "2025-08-27T01:00:00Z",
        "ServiceName": "bedrock.amazonaws.com",
        "ServiceUserName": "bedrock-cross-partition-user-at-123456789012",
        "ServicePassword": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "ServiceSpecificCredentialId": "ACCAEXAMPLE123DEFGHIJKL",
        "UserName": "bedrock-cross-partition-user",
        "Status": "Active"
    }
}
```

## Step 4: Update GovCloud Secret

Take the `ServicePassword` from the output above and update your GovCloud secret:

```bash
# Update the secret in GovCloud with the real API key
aws secretsmanager update-secret \
    --secret-id cross-partition-commercial-creds \
    --secret-string '{
        "bedrock_api_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "region": "us-east-1"
    }' \
    --profile govcloud \
    --region us-gov-west-1
```

## Step 5: Test the Setup

```bash
# Test Claude models
./test-claude.sh

# Test Claude 4.1 with inference profiles
./test-claude-4-1.sh

# Test models discovery
./test-models-endpoint.sh
```

## Step 6: Verify Permissions

Test that the API key has the right permissions:

```bash
# Test listing models
curl -X GET \
  -H "Authorization: Bearer wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" \
  -H "Content-Type: application/json" \
  "https://bedrock.us-east-1.amazonaws.com/foundation-models"

# Test model invocation
curl -X POST \
  -H "Authorization: Bearer wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" \
  -H "Content-Type: application/json" \
  -d '{
    "anthropic_version": "bedrock-2023-05-31",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello"}]
  }' \
  "https://bedrock-runtime.us-east-1.amazonaws.com/model/anthropic.claude-3-5-sonnet-20240620-v1:0/invoke"
```

## Security Best Practices

1. **Rotate Keys Regularly**: Set up a reminder to rotate the API key before it expires
2. **Monitor Usage**: Use CloudTrail to monitor API key usage
3. **Least Privilege**: The policy above provides necessary permissions without over-privileging
4. **Secure Storage**: The API key is stored in AWS Secrets Manager with encryption

## Troubleshooting

### Invalid API Key Format Error
If you get "Invalid API Key format" errors, ensure:
- You're using the `ServicePassword` field from the API key creation
- The key is properly formatted in the secret
- The key hasn't expired

### Access Denied Errors
If you get access denied errors:
- Verify the IAM user has the correct policies attached
- Check that Bedrock is available in us-east-1 region
- Ensure the specific model you're trying to use is available

### Inference Profile Errors
For Claude 4.1 and newer models:
- The system will automatically create inference profiles as needed
- Ensure your policy includes `bedrock:CreateInferenceProfile` permission
- Check CloudTrail logs for detailed error information

## Key Expiration

The API key will expire in 6 months (180 days). To renew:

```bash
# List existing credentials
aws iam list-service-specific-credentials \
    --user-name bedrock-cross-partition-user \
    --service-name bedrock.amazonaws.com

# Delete old credential (use the ServiceSpecificCredentialId)
aws iam delete-service-specific-credential \
    --user-name bedrock-cross-partition-user \
    --service-specific-credential-id ACCAEXAMPLE123DEFGHIJKL

# Create new credential
aws iam create-service-specific-credential \
    --user-name bedrock-cross-partition-user \
    --service-name bedrock.amazonaws.com \
    --credential-age-days 180
```

## Cost Considerations

- API key creation is free
- You'll be charged for Bedrock model usage based on tokens processed
- Monitor usage through AWS Cost Explorer
- Consider setting up billing alerts

This setup provides a production-ready API key that will work with all Bedrock models and features needed for cross-partition inference.