# Cross-Partition Inference Infrastructure

This directory contains the CloudFormation templates and deployment scripts for the Cross-Partition Inference MVP.

## Architecture Overview

The infrastructure creates:

- **API Gateway**: REST API with IAM authentication for secure access
- **Lambda Functions**: Main proxy function and dashboard API function
- **DynamoDB**: Request logging table with TTL for automatic cleanup
- **Secrets Manager**: Secure storage for commercial AWS credentials
- **IAM Roles**: Least-privilege roles for Lambda execution and API access

## Files

- `cross-partition-infrastructure.yaml` - Main CloudFormation template
- `deploy.sh` - Infrastructure deployment script
- `deploy-lambda.sh` - Lambda function code deployment script
- `README.md` - This documentation

## Prerequisites

1. **AWS CLI configured** with GovCloud profile:
   ```bash
   aws configure --profile govcloud
   ```

2. **Required tools**:
   - AWS CLI v2
   - jq (for JSON parsing)
   - zip (for Lambda packaging)
   - Python 3.11+ with pip

3. **Permissions**: Your AWS user needs permissions to:
   - Create/update CloudFormation stacks
   - Create IAM roles and policies
   - Create Lambda functions
   - Create API Gateway resources
   - Create DynamoDB tables
   - Create Secrets Manager secrets

## Deployment Steps

### 1. Deploy Infrastructure

```bash
cd infrastructure
./deploy.sh
```

This will:
- Create the CloudFormation stack in GovCloud
- Set up all AWS resources
- Output the API endpoints and resource names

### 2. Update Commercial Credentials

Update the Secrets Manager secret with your actual commercial AWS credentials:

```bash
aws secretsmanager update-secret \
    --secret-id cross-partition-commercial-creds \
    --secret-string '{"aws_access_key_id":"YOUR_KEY","aws_secret_access_key":"YOUR_SECRET","region":"us-east-1"}' \
    --profile govcloud \
    --region us-gov-west-1
```

### 3. Deploy Lambda Code

```bash
./deploy-lambda.sh
```

This will:
- Package the Lambda function with dependencies
- Deploy the code to the created Lambda functions
- Show the API endpoints for testing

### 4. Test the Deployment

Test the dashboard API:
```bash
# Extract your API endpoint first
./scripts/get-config.sh
source config/config.sh
curl -X GET "$API_BASE_URL/dashboard/requests"
```

Test the Bedrock proxy (requires IAM authentication):
```bash
aws apigateway test-invoke-method \
    --rest-api-id YOUR_API_ID \
    --resource-id YOUR_RESOURCE_ID \
    --http-method POST \
    --path-with-query-string /bedrock/invoke-model \
    --body '{"modelId":"anthropic.claude-3-sonnet-20240229-v1:0","body":"{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}]}"}' \
    --profile govcloud \
    --region us-gov-west-1
```

## Stack Outputs

After deployment, the stack provides these outputs:

- **ApiGatewayUrl**: Base URL for the API Gateway
- **BedrockEndpoint**: Full URL for the Bedrock proxy endpoint
- **DashboardApiEndpoint**: Full URL for the dashboard API
- **LambdaFunctionName**: Name of the main Lambda function
- **DashboardLambdaFunctionName**: Name of the dashboard Lambda function
- **SecretsManagerSecretName**: Name of the secrets manager secret
- **DynamoDBTableName**: Name of the DynamoDB table

## Security Features

### IAM Authentication
- API Gateway uses AWS IAM for authentication
- Lambda execution roles follow least-privilege principle
- Secrets Manager access is restricted to specific resources

### Network Security
- API Gateway is regional (not edge-optimized) for GovCloud compliance
- CORS is configured for API access
- All communications use HTTPS/TLS

### Data Protection
- Commercial credentials encrypted at rest in Secrets Manager
- DynamoDB table has TTL for automatic log cleanup (30 days)
- CloudWatch logs for audit trails

## Monitoring and Logging

### CloudWatch Logs
- Lambda function logs are automatically sent to CloudWatch
- Log groups are created with appropriate retention policies
- Structured logging for easy searching and analysis

### DynamoDB Logging
- All cross-partition requests are logged to DynamoDB
- Includes source/destination partition information
- Request/response metadata for performance monitoring
- Automatic cleanup after 30 days

### API Gateway Logging
- Access logs can be enabled for additional monitoring
- Request/response logging available for debugging

## Cost Optimization

### Pay-per-use Resources
- Lambda functions (pay per invocation)
- DynamoDB (on-demand billing)
- API Gateway (pay per request)

### Automatic Cleanup
- DynamoDB TTL removes old logs automatically
- CloudWatch log retention policies prevent unbounded growth

### Resource Sizing
- Lambda functions sized appropriately for workload
- DynamoDB uses on-demand billing to scale automatically

## Troubleshooting

### Common Issues

1. **Stack deployment fails**:
   - Check IAM permissions
   - Verify AWS CLI profile configuration
   - Check CloudFormation events for specific errors

2. **Lambda function errors**:
   - Check CloudWatch logs for the Lambda function
   - Verify Secrets Manager secret format
   - Test commercial AWS credentials manually

3. **API Gateway 403 errors**:
   - Verify IAM authentication
   - Check API Gateway resource policies
   - Ensure proper CORS configuration

4. **Cross-partition connectivity issues**:
   - Verify commercial AWS credentials
   - Check network connectivity from GovCloud to Commercial
   - Test Bedrock access from commercial account

### Debugging Commands

View stack events:
```bash
aws cloudformation describe-stack-events \
    --stack-name cross-partition-inference-mvp \
    --profile govcloud \
    --region us-gov-west-1
```

Check Lambda logs:
```bash
aws logs describe-log-groups \
    --log-group-name-prefix /aws/lambda/CrossPartition \
    --profile govcloud \
    --region us-gov-west-1
```

Test secret retrieval:
```bash
aws secretsmanager get-secret-value \
    --secret-id cross-partition-commercial-creds \
    --profile govcloud \
    --region us-gov-west-1
```

## Cleanup

To remove all resources:

```bash
aws cloudformation delete-stack \
    --stack-name cross-partition-inference-mvp \
    --profile govcloud \
    --region us-gov-west-1
```

**Note**: This will delete all resources including logs and stored credentials. Make sure to backup any important data before cleanup.

## Next Steps

After successful deployment:

1. **Configure Monitoring** - Set up CloudWatch alarms and dashboards
2. **Security Review** - Review IAM policies and access patterns
4. **Performance Testing** - Test with realistic workloads
5. **Documentation** - Create user guides and operational procedures