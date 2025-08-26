# Cross-Partition Lambda Function

This Lambda function serves as a proxy to forward requests from AWS GovCloud to Commercial Bedrock services.

## Features

- **Cross-partition proxy**: Forwards Bedrock API calls from GovCloud to Commercial
- **Credential management**: Retrieves commercial AWS credentials from Secrets Manager
- **Request logging**: Logs all requests to DynamoDB for dashboard visibility
- **Error handling**: Comprehensive error handling and logging
- **Audit trail**: Complete audit trail with request/response metadata

## Environment Variables

- `COMMERCIAL_CREDENTIALS_SECRET`: Name of the Secrets Manager secret containing commercial AWS credentials (default: 'cross-partition-commercial-creds')
- `REQUEST_LOG_TABLE`: Name of the DynamoDB table for request logging (default: 'cross-partition-requests')

## Required IAM Permissions

The Lambda execution role needs the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws-us-gov:secretsmanager:*:*:secret:cross-partition-commercial-creds*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem"
            ],
            "Resource": "arn:aws-us-gov:dynamodb:*:*:table/cross-partition-requests"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws-us-gov:logs:*:*:*"
        }
    ]
}
```

## Secrets Manager Format

The commercial credentials secret should contain:

```json
{
    "aws_access_key_id": "AKIA...",
    "aws_secret_access_key": "...",
    "aws_session_token": "..." // Optional for temporary credentials
}
```

## Request Format

The Lambda expects API Gateway proxy integration events with the following body format:

```json
{
    "modelId": "anthropic.claude-3-sonnet-20240229-v1:0",
    "contentType": "application/json",
    "accept": "application/json",
    "body": "{\"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}"
}
```

## Response Format

Successful responses include partition information in headers:

```json
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json",
        "X-Request-ID": "uuid",
        "X-Source-Partition": "govcloud",
        "X-Destination-Partition": "commercial"
    },
    "body": "{\"response\": \"...\"}"
}
```

## DynamoDB Log Schema

Each request is logged to DynamoDB with the following structure:

```json
{
    "requestId": "uuid",
    "timestamp": "2024-01-01T12:00:00Z",
    "sourcePartition": "govcloud",
    "destinationPartition": "commercial",
    "modelId": "anthropic.claude-3-sonnet-20240229-v1:0",
    "userArn": "arn:aws-us-gov:iam::123456789012:user/testuser",
    "sourceIP": "192.168.1.1",
    "requestSize": 1024,
    "responseSize": 2048,
    "latency": 1500,
    "success": true,
    "statusCode": 200,
    "ttl": 1704067200
}
```

## Deployment

1. Install dependencies: `pip install -r requirements.txt -t .`
2. Create deployment package: `zip -r lambda-function.zip .`
3. Deploy using AWS CLI, CloudFormation, or CDK