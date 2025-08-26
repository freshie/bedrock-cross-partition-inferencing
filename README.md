# Cross-Partition Inference MVP

A secure, internet-based solution for accessing AWS Commercial Bedrock models from AWS GovCloud via API endpoints.

## 🏛️ Overview

This MVP enables AWS GovCloud users to access Commercial partition Bedrock AI models when local resources are constrained or unavailable. The solution provides:

- **Secure cross-partition proxy** for Bedrock API calls
- **Model discovery API** to list available Commercial Bedrock models
- **Complete audit trail** with request logging
- **Simple deployment** with automated scripts

## 🏗️ Architecture

```
GovCloud                           Commercial
┌─────────────────────────┐       ┌──────────────────┐
│                         │       │                  │
│  API Gateway            │       │   Amazon         │
│  ┌─────────────────┐    │  HTTPS│   Bedrock        │
│  │ /bedrock/       │    │   ──► │                  │
│  │ invoke-model    │    │       │   AI Models      │
│  │                 │    │       │   (Claude, etc.) │
│  │ /bedrock/models │    │       │                  │
│  └─────────────────┘    │       └──────────────────┘
│           │             │
│  ┌─────────────────┐    │
│  │ Lambda Proxy    │    │
│  │ Function        │    │
│  └─────────────────┘    │
│                         │
│  DynamoDB (Logs)        │
│  Secrets Manager        │
└─────────────────────────┘
```

## 📁 Project Structure

```
├── deploy-mvp.sh              # Complete deployment script
├── test-cross-partition.sh    # End-to-end testing script
├── aws-profile-guide.md       # AWS profile usage guide
├── infrastructure/            # CloudFormation templates
│   ├── cross-partition-infrastructure.yaml
│   ├── deploy.sh
│   ├── deploy-lambda.sh
│   └── README.md
├── lambda/                    # Lambda function code
│   ├── lambda_function.py
│   ├── requirements.txt
│   ├── test_lambda.py
│   └── README.md
└── test-models-endpoint.sh    # Test script for models API
└── .kiro/specs/              # Feature specifications
    └── cross-partition-inference/
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI v2** with GovCloud profile configured
2. **jq** for JSON parsing
3. **Commercial AWS account** with Bedrock access
4. **Required permissions** in GovCloud account

### Step 1: Generate Bedrock API Key

Generate a Bedrock API key in your **Commercial AWS account**:

1. Sign in to **Commercial AWS Console** (not GovCloud)
2. Navigate to **Amazon Bedrock** → **API Keys**
3. Choose **Generate long-term API key**
4. Set expiration (recommend 90 days for testing)
5. **Copy the API key** - you'll need it after deployment

### Step 2: Deploy the Solution

```bash
./deploy-mvp.sh
```

This script will:
1. Deploy all infrastructure (CloudFormation)
2. Deploy Lambda functions
3. Run basic connectivity tests
4. Provide API endpoint URLs

### Manual Step-by-Step

1. **Deploy Infrastructure**:
   ```bash
   cd infrastructure
   ./deploy.sh
   ```

2. **Update Commercial Credentials**:
   ```bash
   aws secretsmanager update-secret \
       --secret-id cross-partition-commercial-creds \
       --secret-string '{"aws_access_key_id":"YOUR_KEY","aws_secret_access_key":"YOUR_SECRET","region":"us-east-1"}' \
       --profile govcloud \
       --region us-gov-west-1
   ```

3. **Deploy Lambda Code**:
   ```bash
   cd infrastructure
   ./deploy-lambda.sh
   ```

4. **Test the APIs**:
   ```bash
   ./test-models-endpoint.sh
   ./test-cross-partition.sh
   ```

5. **Test Everything**:
   ```bash
   ./test-cross-partition.sh
   ```

## 🎯 Features

### Cross-Partition Proxy
- Secure HTTPS communication between partitions
- Automatic credential management via Secrets Manager
- Complete request/response logging
- Error handling and retry logic

### Model Discovery API
- **List available models** from Commercial Bedrock
- **Model capabilities** and supported features
- **Real-time model availability** checking
- **Cross-partition model access** verification



### Security & Compliance
- IAM-based authentication
- Encrypted credential storage
- Complete audit trails
- Automatic log cleanup (30-day TTL)
- No sensitive data exposure

### Monitoring & Observability
- CloudWatch logs for debugging
- DynamoDB request logging
- Performance metrics (latency, sizes)
- Success/failure tracking

## 🔧 Configuration

### AWS Profiles
- **govcloud**: For GovCloud resources and deployment
- **default**: For commercial AWS access (stored in Secrets Manager)

See `aws-profile-guide.md` for detailed profile usage.

### Environment Variables
- `COMMERCIAL_CREDENTIALS_SECRET`: Secrets Manager secret name
- `REQUEST_LOG_TABLE`: DynamoDB table for request logs

## 🧪 Testing

### Automated Testing
```bash
./test-cross-partition.sh
```

Tests include:
- Dashboard API connectivity
- Bedrock proxy authentication
- CloudWatch logs verification
- DynamoDB table access
- Website accessibility

### Manual Testing

1. **Dashboard API**:
   ```bash
   curl -X GET "https://YOUR_API_ID.execute-api.us-gov-west-1.amazonaws.com/v1/dashboard/requests"
   ```

2. **Models Discovery API**:
   ```bash
   ./test-models-endpoint.sh
   ```

3. **Cross-Partition Request**:
   ```bash
   # Use AWS CLI with IAM authentication
   aws apigateway test-invoke-method \
       --rest-api-id YOUR_API_ID \
       --resource-id YOUR_RESOURCE_ID \
       --http-method POST \
       --body '{"modelId":"anthropic.claude-3-haiku-20240307-v1:0","body":"..."}' \
       --profile govcloud
   ```

## 📊 API Usage

### Available Endpoints

1. **Bedrock Proxy**: `/v1/bedrock/invoke-model`
   - Forwards requests to Commercial Bedrock
   - Handles authentication and logging
   - Returns AI model responses

2. **Models Discovery**: `/v1/bedrock/models`
   - Lists available Commercial Bedrock models
   - Shows model capabilities and features
   - Real-time availability checking

3. **Request Logs**: `/v1/dashboard/requests`
   - Returns logged cross-partition requests
   - Includes performance metrics
   - Filterable by time and status

## 🔒 Security

### Data Protection
- All communications use HTTPS/TLS
- Commercial credentials encrypted in Secrets Manager
- No sensitive data in logs or UI
- Automatic credential rotation support

### Access Control
- IAM-based API authentication
- Least-privilege Lambda roles
- VPC isolation (future roadmap)
- Audit trail for all requests

### Compliance
- Complete request logging
- Data classification tracking
- Retention policies (30-day TTL)
- Cross-partition data flow visibility

## 🛠️ Troubleshooting

### Common Issues

1. **"Connection Error" in Dashboard**:
   - Check API Gateway endpoint configuration
   - Verify CORS settings
   - Check browser console for errors

2. **Cross-Partition Requests Fail**:
   - Verify commercial credentials in Secrets Manager
   - Check Lambda CloudWatch logs
   - Test commercial account access manually

3. **No Data in Dashboard**:
   - Make some test requests first
   - Check DynamoDB table for entries
   - Verify dashboard API endpoint

### Debug Commands

```bash
# Check CloudWatch logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/CrossPartition --profile govcloud

# Test commercial credentials
aws secretsmanager get-secret-value --secret-id cross-partition-commercial-creds --profile govcloud

# Check DynamoDB entries
aws dynamodb scan --table-name cross-partition-requests --profile govcloud
```

## 🗺️ Roadmap

See `.kiro/specs/cross-partition-inference/roadmap.md` for future enhancements:

- **Phase 2**: Enhanced Security & Governance
- **Phase 3**: Advanced Networking (VPN, Direct Connect)
- **Phase 4**: Enterprise Features (Multi-region, HA)
- **Phase 5**: Advanced AI/ML Features

## 📝 Documentation

- `infrastructure/README.md` - Infrastructure deployment details
- `lambda/README.md` - Lambda function documentation

- `aws-profile-guide.md` - AWS profile usage guide

## 🤝 Contributing

1. Follow the existing code structure
2. Update documentation for changes
3. Test thoroughly before committing
4. Use the provided `.gitignore` to protect credentials

## 📄 License

This project is for internal use and follows AWS security best practices.

## 🆘 Support

For issues or questions:
1. Check the troubleshooting section
2. Review CloudWatch logs
3. Test individual components
4. Consult the detailed documentation in each directory