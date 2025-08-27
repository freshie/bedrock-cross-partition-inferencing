# Cross-Partition AI Inference System

A secure, production-ready solution for accessing AWS Commercial Bedrock AI models from AWS GovCloud environments via internet-based API proxy.

## 🏛️ Overview

This system enables AWS GovCloud users to seamlessly access Commercial partition Bedrock AI models including **Claude 4.1**, **Claude 3.5 Sonnet**, and other advanced AI models when local GovCloud resources are constrained or unavailable. 

### Key Capabilities

- **🤖 Advanced AI Models**: Access to Claude 4.1, Claude 3.5 Sonnet, Nova, Llama, and other cutting-edge models
- **🔒 Secure Cross-Partition Proxy**: Encrypted HTTPS communication with full audit trails
- **🎯 Automatic Inference Profiles**: Seamless handling of models requiring inference profiles
- **📊 Model Discovery API**: Real-time listing of available Commercial Bedrock models
- **🔑 Flexible Authentication**: Support for both Bedrock API keys and AWS credentials
- **📈 Complete Observability**: Request logging, performance metrics, and monitoring
- **🚀 Simple Deployment**: Automated infrastructure deployment and testing

## 🏗️ Architecture

```
AWS GovCloud (us-gov-west-1)                    AWS Commercial (us-east-1)
┌─────────────────────────────────┐             ┌──────────────────────────┐
│                                 │             │                          │
│  🌐 API Gateway                 │             │  🤖 Amazon Bedrock       │
│  ┌─────────────────────────┐    │   HTTPS     │  ┌─────────────────────┐ │
│  │ /v1/bedrock/invoke-model│────┼─────────────┼─►│ Claude 4.1          │ │
│  │ /v1/bedrock/models      │    │   Internet  │  │ Claude 3.5 Sonnet   │ │
│  │ /v1/dashboard/requests  │    │             │  │ Nova Premier/Pro    │ │
│  └─────────────────────────┘    │             │  │ Llama 4 Scout       │ │
│             │                   │             │  │ + Inference Profiles│ │
│  ⚡ Lambda Proxy Function       │             │  └─────────────────────┘ │
│  ┌─────────────────────────┐    │             │                          │
│  │ • API Key Authentication│    │             │  🔑 Bedrock API Keys     │
│  │ • Inference Profile Mgmt│    │             │  ┌─────────────────────┐ │
│  │ • Request Routing       │    │             │  │ Long-term API Keys  │ │
│  │ • Error Handling        │    │             │  │ Auto-expiration     │ │
│  │ • Audit Logging         │    │             │  │ Enhanced Permissions│ │
│  └─────────────────────────┘    │             │  └─────────────────────┘ │
│                                 │             └──────────────────────────┘
│  🗄️ Storage & Security          │
│  ┌─────────────────────────┐    │
│  │ Secrets Manager         │    │
│  │ • Commercial API Keys   │    │
│  │ • Encrypted Storage     │    │
│  └─────────────────────────┘    │
│                                 │
│  ┌─────────────────────────┐    │
│  │ DynamoDB Logs           │    │
│  │ • Request Audit Trail   │    │
│  │ • Performance Metrics   │    │
│  │ • 30-day TTL            │    │
│  └─────────────────────────┘    │
└─────────────────────────────────┘

📊 **Detailed Architecture**: See [ARCHITECTURE.md](ARCHITECTURE.md)  
🎨 **Visual Diagram**: [Cross-Partition Inference Flow](https://app.diagrams.net/) *(Draw.io link to be added)*

> **Note**: The Draw.io diagram provides a comprehensive visual representation including:
> - Complete request/response flows
> - Security boundaries and encryption points  
> - Error handling and retry mechanisms
> - Inference profile creation logic
> - Monitoring and audit touchpoints
```

## 🔑 Key Requirements

### Commercial AWS Account Requirements
- **Bedrock Model Access**: Enable Claude 4.1, Claude 3.5 Sonnet, Nova, Llama models
- **Enhanced IAM Policy**: Inference profile creation and management permissions
- **API Key Generation**: Long-term Bedrock API key with enhanced permissions
- **Region**: Models must be available in `us-east-1`

### GovCloud Account Requirements  
- **API Gateway**: REST API with Lambda integration
- **Lambda Function**: Python 3.9+ runtime with enhanced permissions
- **Secrets Manager**: Secure storage for Commercial credentials
- **DynamoDB**: Request logging and audit trail storage
- **IAM Roles**: Proper permissions for cross-service access

### Network Requirements
- **Internet Connectivity**: HTTPS access from GovCloud to Commercial AWS
- **DNS Resolution**: Ability to resolve `bedrock-runtime.us-east-1.amazonaws.com`
- **Firewall Rules**: Outbound HTTPS (port 443) from Lambda to internet

## 📁 Project Structure

```
├── 📋 ARCHITECTURE.md                          # Detailed architecture documentation
├── 🚀 deploy-mvp.sh                           # Complete deployment automation
├── 🧪 Test Scripts
│   ├── test-cross-partition.sh                # End-to-end system testing
│   ├── test-claude.sh                         # Claude 3.5 Sonnet testing
│   ├── test-claude-4-1.sh                     # Claude 4.1 inference profile testing
│   └── test-models-endpoint.sh                # Model discovery API testing
├── 📚 Documentation & Guides
│   ├── aws-profile-guide.md                   # AWS CLI profile configuration
│   ├── create-comprehensive-bedrock-api-key.md # API key creation guide
│   ├── create-real-bedrock-api-key.md         # Alternative API key guide
│   └── bedrock-enhanced-policy.json           # Enhanced IAM policy template
├── 🏗️ infrastructure/                         # CloudFormation & deployment
│   ├── cross-partition-infrastructure.yaml    # Main infrastructure template
│   ├── deploy.sh                              # Infrastructure deployment
│   ├── deploy-lambda.sh                       # Lambda function deployment
│   └── README.md                              # Infrastructure documentation
├── ⚡ lambda/                                 # Lambda function implementation
│   ├── lambda_function.py                     # Main proxy function
│   ├── requirements.txt                       # Python dependencies
│   ├── test_lambda.py                         # Unit tests
│   └── README.md                              # Function documentation
└── 📋 .kiro/specs/                           # Feature specifications & roadmap
    └── cross-partition-inference/
        ├── requirements.md                    # System requirements
        ├── design.md                          # Technical design
        ├── tasks.md                           # Implementation tasks
        └── roadmap.md                         # Future enhancements
```

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI v2** with GovCloud profile configured
2. **jq** for JSON parsing
3. **Commercial AWS account** with Bedrock access
4. **Required permissions** in GovCloud account

### Step 1: Setup Commercial AWS Account

#### Generate Enhanced Bedrock API Key

Create a Bedrock API key with inference profile permissions in your **Commercial AWS account**:

1. **Create Enhanced IAM Policy** (see `bedrock-enhanced-policy.json`):
   ```bash
   aws iam create-policy \
     --policy-name BedrockEnhancedAccess \
     --policy-document file://bedrock-enhanced-policy.json
   ```

2. **Generate API Key with Enhanced Permissions**:
   ```bash
   # Follow the comprehensive guide
   ./create-comprehensive-bedrock-api-key.md
   ```

3. **Enable Required Models**:
   - Navigate to **Amazon Bedrock Console** → **Model Access**
   - Enable: Claude 4.1, Claude 3.5 Sonnet, Nova Premier, Llama models
   - Verify inference profiles are available

#### What You'll Get
- **API Key Format**: `bedrock-api-user+1-at-ACCOUNT:BASE64_SECRET`
- **Enhanced Permissions**: Inference profile creation and management
- **Model Access**: Claude 4.1, Nova, and all advanced models
- **Automatic Expiration**: Configurable (90 days recommended for testing)

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

2. **Store Commercial Bedrock API Key**:
   ```bash
   # Store the Bedrock API key (preferred method)
   aws secretsmanager update-secret \
       --secret-id cross-partition-commercial-creds \
       --secret-string '{"bedrock_api_key":"YOUR_BASE64_API_KEY","region":"us-east-1"}' \
       --profile govcloud \
       --region us-gov-west-1
   
   # Alternative: AWS credentials (if API key not available)
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
# Test basic cross-partition functionality
./test-cross-partition.sh

# Test Claude 3.5 Sonnet
./test-claude.sh

# Test Claude 4.1 (requires inference profile)
./test-claude-4-1.sh

# Test model discovery API
./test-models-endpoint.sh
```

### Test Coverage
- ✅ **Cross-partition connectivity** and authentication
- ✅ **Claude 4.1 inference** via inference profiles
- ✅ **Claude 3.5 Sonnet** direct model access
- ✅ **Model discovery API** listing all available models
- ✅ **Dashboard API** for request logs and metrics
- ✅ **Error handling** and retry logic
- ✅ **CloudWatch logging** and DynamoDB audit trails

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

### Core Documentation
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Complete system architecture and design
- **[README.md](README.md)** - This file: Quick start and overview

### Setup & Configuration Guides  
- **[create-comprehensive-bedrock-api-key.md](create-comprehensive-bedrock-api-key.md)** - Bedrock API key creation
- **[aws-profile-guide.md](aws-profile-guide.md)** - AWS CLI profile configuration
- **[bedrock-enhanced-policy.json](bedrock-enhanced-policy.json)** - Enhanced IAM policy template

### Component Documentation
- **[infrastructure/README.md](infrastructure/README.md)** - Infrastructure deployment details
- **[lambda/README.md](lambda/README.md)** - Lambda function implementation
- **[.kiro/specs/cross-partition-inference/](/.kiro/specs/cross-partition-inference/)** - Feature specifications

### Testing & Validation
- All test scripts include inline documentation
- CloudWatch logs provide detailed execution traces
- DynamoDB audit logs for request analysis

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