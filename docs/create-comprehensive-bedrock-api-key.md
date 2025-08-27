# Create Comprehensive Bedrock API Key

This guide will help you create a new Bedrock API key with full permissions for cross-partition inference, including model listing, invocation, and inference profile management.

## Prerequisites

- Access to AWS Commercial account (not GovCloud)
- IAM permissions to create users and policies
- AWS CLI configured for commercial account

## Step 1: Create IAM Policy

Create a comprehensive IAM policy that includes all necessary Bedrock permissions:

```bash
# Create the policy document
cat > bedrock-full-access-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "BedrockModelAccess",
            "Effect": "Allow",
            "Action": [
                "bedrock:ListFoundationModels",
                "bedrock:GetFoundationModel",
                "bedrock:ListModelCustomizationJobs",
                "bedrock:GetModelCustomizationJob"
            ],
            "Resource": "*"
        },
        {
            "Sid": "BedrockInference",
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream"
            ],
            "Resource": [
                "arn:aws:bedrock:*::foundation-model/*",
                "arn:aws:bedrock:*:*:custom-model/*",
                "arn:aws:bedrock:*:*:inference-profile/*"
            ]
        },
        {
            "Sid": "BedrockInferenceProfiles",
            "Effect": "Allow",
            "Action": [
                "bedrock:CreateInferenceProfile",
                "bedrock:GetInferenceProfile",
                "bedrock:ListInferenceProfiles",
                "bedrock:DeleteInferenceProfile",
                "bedrock:UpdateInferenceProfile",
                "bedrock:TagResource",
                "bedrock:UntagResource",
                "bedrock:ListTagsForResource"
            ],
            "Resource": [
                "arn:aws:bedrock:*:*:inference-profile/*",
                "arn:aws:bedrock:*::foundation-model/*"
            ]
        },
        {
            "Sid": "BedrockModelInvocation",
            "Effect": "Allow",
            "Action": [
                "bedrock:Converse",
                "bedrock:ConverseStream"
            ],
            "Resource": [
                "arn:aws:bedrock:*::foundation-model/*",
                "arn:aws:bedrock:*:*:inference-profile/*"
            ]
        },
        {
            "Sid": "BedrockKnowledgeBase",
            "Effect": "Allow",
            "Action": [
                "bedrock:Retrieve",
                "bedrock:RetrieveAndGenerate"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create the IAM policy
aws iam create-policy \
    --policy-name BedrockCrossPartitionFullAccess \
    --policy-document file://bedrock-full-access-policy.json \
    --description "Full Bedrock access for cross-partition inference including inference profiles"
```

## Step 2: Create IAM User

Create a dedicated IAM user for cross-partition Bedrock access:

```bash
# Create the IAM user
aws iam create-user \
    --user-name bedrock-cross-partition-user \
    --tags Key=Purpose,Value=CrossPartitionInference Key=Service,Value=Bedrock

# Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Attach the policy to the user
aws iam attach-user-policy \
    --user-name bedrock-cross-partition-user \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/BedrockCrossPartitionFullAccess"
```

## Step 3: Create Access Keys

Generate access keys for the user:

```bash
# Create access keys
aws iam create-access-key \
    --user-name bedrock-cross-partition-user \
    --output table
```

**Important**: Save the `AccessKeyId` and `SecretAccessKey` from the output. You won't be able to retrieve the secret key again.

## Step 4: Test the API Key

Test the new API key to ensure it has the correct permissions:

```bash
# Set temporary environment variables (replace with your actual keys)
export AWS_ACCESS_KEY_ID="YOUR_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="YOUR_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="us-east-1"

# Test 1: List foundation models
echo "Testing model listing..."
aws bedrock list-foundation-models --region us-east-1

# Test 2: Test model invocation (using a simple model)
echo "Testing model invocation..."
aws bedrock-runtime invoke-model \
    --region us-east-1 \
    --model-id "amazon.titan-text-lite-v1" \
    --content-type "application/json" \
    --accept "application/json" \
    --body '{"inputText":"Hello, this is a test","textGenerationConfig":{"maxTokenCount":50}}' \
    /tmp/response.json

cat /tmp/response.json

# Test 3: List inference profiles
echo "Testing inference profile listing..."
aws bedrock list-inference-profiles --region us-east-1

# Clean up test file
rm -f /tmp/response.json
```

## Step 5: Create Bedrock API Key Format

For the cross-partition system, we need to create a properly formatted API key. The system expects a base64-encoded string containing the access credentials:

```bash
# Create the API key in the correct format
ACCESS_KEY_ID="YOUR_ACCESS_KEY_ID"
SECRET_ACCESS_KEY="YOUR_SECRET_ACCESS_KEY"

# Create base64 encoded API key
BEDROCK_API_KEY=$(echo -n "${ACCESS_KEY_ID}:${SECRET_ACCESS_KEY}" | base64)

echo "Your Bedrock API Key:"
echo "$BEDROCK_API_KEY"
```

## Step 6: Update the Cross-Partition Secret

Update your GovCloud secret with the new API key:

```bash
# Update the secret in GovCloud
aws secretsmanager update-secret \
    --secret-id cross-partition-commercial-creds \
    --secret-string "{\"bedrock_api_key\":\"${BEDROCK_API_KEY}\",\"region\":\"us-east-1\"}" \
    --profile govcloud \
    --region us-gov-west-1
```

## Step 7: Verify Cross-Partition Access

Test the cross-partition inference with the new API key:

```bash
# Test Claude 3.5 Sonnet
./test-claude.sh

# Test Claude 4.1 with inference profiles
./test-claude-4-1.sh

# Test model discovery
./test-models-endpoint.sh
```

## Troubleshooting

### Permission Issues

If you get permission errors, ensure the policy includes all necessary actions:

```bash
# Check attached policies
aws iam list-attached-user-policies --user-name bedrock-cross-partition-user

# Check policy details
aws iam get-policy-version \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/BedrockCrossPartitionFullAccess" \
    --version-id v1
```

### Model Access Issues

Some models may require explicit access requests:

1. Go to AWS Bedrock Console
2. Navigate to "Model access"
3. Request access for specific models (Claude, Nova, etc.)
4. Wait for approval (usually immediate for most models)

### Inference Profile Issues

If inference profile creation fails:

```bash
# Check existing inference profiles
aws bedrock list-inference-profiles --region us-east-1

# Check if the model supports inference profiles
aws bedrock get-foundation-model \
    --model-identifier "anthropic.claude-opus-4-1-20250805-v1:0" \
    --region us-east-1
```

## Security Best Practices

1. **Rotate Keys Regularly**: Set up a rotation schedule for the access keys
2. **Monitor Usage**: Enable CloudTrail logging for Bedrock API calls
3. **Least Privilege**: Review and minimize permissions as needed
4. **Secure Storage**: Store the API key securely in Secrets Manager

## Key Features Enabled

With this comprehensive API key, your cross-partition system can:

✅ **List all available models** in commercial Bedrock  
✅ **Invoke any accessible model** including Claude 4.1  
✅ **Create inference profiles** automatically for models that require them  
✅ **Use both direct invocation and inference profiles**  
✅ **Access the latest AI models** as they become available  

## Next Steps

1. Test all functionality with the new API key
2. Monitor usage and costs in the commercial account
3. Set up CloudWatch alarms for unusual activity
4. Document the setup for your team

Your cross-partition inference system is now ready to use Claude 4.1 and all other advanced Bedrock models!