# Creating a Bedrock API Key for Cross-Partition Access

## Prerequisites
- Access to a commercial AWS account (not GovCloud)
- Permissions to create IAM users and Bedrock API keys
- Bedrock service enabled in us-east-1

## Step 1: Create Bedrock API Key in Commercial AWS

### Option A: Using AWS Console
1. Log into your commercial AWS account
2. Navigate to Amazon Bedrock console
3. Go to "API Keys" section
4. Click "Create API Key"
5. Give it a name like "govcloud-cross-partition-key"
6. Select appropriate permissions for the models you want to access
7. Copy the generated API key (base64 encoded string)

### Option B: Using AWS CLI (in commercial account)
```bash
# Switch to commercial AWS profile
aws configure --profile commercial

# Create Bedrock API key
aws bedrock create-api-key \
    --api-key-name "govcloud-cross-partition-key" \
    --description "API key for GovCloud cross-partition inference" \
    --region us-east-1 \
    --profile commercial
```

## Step 2: Update GovCloud Secret

Once you have the API key, update the secret in GovCloud:

```bash
# Update the secret with your actual API key
aws secretsmanager update-secret \
    --secret-id cross-partition-commercial-creds \
    --secret-string '{"bedrock_api_key":"YOUR_ACTUAL_API_KEY_HERE","region":"us-east-1"}' \
    --profile govcloud \
    --region us-gov-west-1
```

## Step 3: Test the System

Run the test suite to verify everything works:

```bash
# Test the deployment
./test-cross-partition.sh

# Test models endpoint specifically
./test-models-endpoint.sh
```

## Important Notes

- The API key should be a base64-encoded string
- Make sure the commercial account has access to the Bedrock models you want to use
- The API key needs permissions for both listing models and invoking models
- Test with a simple model first (like Amazon Titan or Nova Micro)

## Troubleshooting

If you get permission errors:
1. Verify the API key has correct permissions in commercial AWS
2. Check that Bedrock is enabled in us-east-1
3. Ensure the models you're trying to access are available in your commercial account
4. Check CloudWatch logs for detailed error messages