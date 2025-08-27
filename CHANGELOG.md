# Changelog

All notable changes to the Cross-Partition AI Inference System will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-08-27 - "Claude 4.1 Ready" Release

### 🎉 Major Enhancement - Claude 4.1 Support

Successfully implemented and tested Claude 4.1 (Opus) cross-partition inference with proper Bedrock API key authentication.

### ✨ Features Added

#### Authentication & Security
- **Proper Bedrock API Keys**: Implemented service-specific credentials for Bedrock authentication
- **Enhanced Lambda Function**: Added `requests` library support for HTTP-based Bedrock API calls
- **Dual Authentication Support**: API key authentication with AWS credentials fallback
- **Comprehensive IAM Policies**: Full Bedrock access including inference profiles

#### Model Support
- **Claude 4.1 (Opus) Support**: Successfully tested cross-partition inference with latest Anthropic model
- **Inference Profile Automation**: Automatic handling of models requiring system-defined inference profiles
- **Enhanced Error Handling**: Better error messages and debugging information

#### Documentation & Configuration
- **API Key Reference Documentation**: Comprehensive guides for Bedrock API key creation and management
- **Configuration Management**: Improved local configuration system with API endpoint management
- **Testing Scripts**: Enhanced test scripts with better error reporting and status indicators

### 🔧 Technical Improvements

#### Lambda Function Enhancements
- **Dependencies**: Added `requests==2.31.0` to requirements.txt
- **API Key Handling**: Proper base64 decoding and format validation
- **Error Handling**: Enhanced error messages for debugging
- **Logging**: Improved CloudWatch logging for troubleshooting

#### Infrastructure
- **Secrets Manager**: Updated with proper Bedrock service-specific credentials
- **IAM Policies**: Enhanced with comprehensive Bedrock permissions
- **Deployment**: Improved Lambda deployment with dependency management

### 🧪 Testing & Validation
- **Claude 4.1 Testing**: Successful cross-partition inference with 200-token responses
- **API Key Validation**: Confirmed proper Bedrock API key format and authentication
- **End-to-End Flow**: Validated complete GovCloud → Commercial AWS → Bedrock flow

### 📚 Documentation Updates
- **BEDROCK_API_KEY_REFERENCE.md**: New reference guide for API key management
- **bedrock-api-key-config.json**: Local configuration tracking for API keys
- **Enhanced Error Troubleshooting**: Better debugging guides and common issues

### 🔒 Security Enhancements
- **Service-Specific Credentials**: Using proper Bedrock API keys instead of general AWS access keys
- **Credential Rotation**: 6-month expiration tracking for API keys
- **Secure Storage**: Proper Secrets Manager integration with encrypted storage

## [1.0.0] - 2025-08-27 - "Over the Internet" Release

### 🎉 Initial Release

The first production-ready version of the Cross-Partition AI Inference System, enabling secure access to AWS Commercial Bedrock models from AWS GovCloud environments via internet-based proxy.

### ✨ Features Added

#### Core Functionality
- **Cross-Partition Proxy**: Secure HTTPS communication between GovCloud and Commercial AWS
- **Advanced AI Model Support**: Claude 4.1, Claude 3.5 Sonnet, Nova Premier, Llama 4 Scout
- **Automatic Inference Profiles**: Seamless handling of models requiring inference profiles
- **Dual Authentication**: Support for both Bedrock API keys and AWS credentials
- **Model Discovery API**: Real-time listing of available Commercial Bedrock models

#### Infrastructure
- **API Gateway**: REST API with Lambda proxy integration
- **Lambda Function**: Python-based request routing and authentication
- **Secrets Manager**: Secure storage of Commercial AWS credentials
- **DynamoDB**: Complete audit trail and request logging
- **CloudFormation**: Automated infrastructure deployment

#### Security & Compliance
- **IAM-based Authentication**: Secure API access control
- **Encrypted Credential Storage**: Secrets Manager with KMS encryption
- **Complete Audit Trail**: Request/response logging with 30-day TTL
- **Enhanced Permissions**: Inference profile creation and management
- **HTTPS/TLS Encryption**: All communications encrypted in transit

#### Testing & Validation
- **Automated Test Suite**: Comprehensive testing scripts for all components
- **Claude 4.1 Testing**: Specific test for inference profile functionality
- **Model Discovery Testing**: Validation of Commercial model access
- **End-to-End Testing**: Complete cross-partition request validation

#### Documentation
- **Comprehensive README**: Quick start guide and feature overview
- **Architecture Documentation**: Detailed system design and component interaction
- **Setup Guides**: Step-by-step Commercial and GovCloud account configuration
- **API Key Creation**: Enhanced Bedrock API key generation with inference profiles
- **Testing Documentation**: Complete test coverage and validation procedures

### 🏗️ Architecture Components

#### GovCloud (us-gov-west-1)
- API Gateway with REST endpoints
- Lambda proxy function with enhanced error handling
- Secrets Manager for credential storage
- DynamoDB for request audit logging

#### Commercial (us-east-1)
- Amazon Bedrock with advanced AI models
- Inference profiles for high-availability routing
- Enhanced Bedrock API keys with extended permissions

### 🔑 Supported Models

#### Claude Models
- **Claude 4.1**: `anthropic.claude-opus-4-1-20250805-v1:0` (via inference profile)
- **Claude 3.5 Sonnet v2**: `anthropic.claude-3-5-sonnet-20241022-v2:0`
- **Claude 3.5 Sonnet**: `anthropic.claude-3-5-sonnet-20240620-v1:0`

#### Amazon Nova Models
- **Nova Premier**: `amazon.nova-premier-v1:0`
- **Nova Pro**: `amazon.nova-pro-v1:0`
- **Nova Lite**: `amazon.nova-lite-v1:0`
- **Nova Micro**: `amazon.nova-micro-v1:0`

#### Meta Llama Models
- **Llama 4 Scout**: `meta.llama4-scout-17b-instruct-v1:0`
- **Llama 4 Maverick**: `meta.llama4-maverick-17b-instruct-v1:0`
- **Llama 3.3 70B**: `meta.llama3-3-70b-instruct-v1:0`

### 📊 API Endpoints

- `POST /v1/bedrock/invoke-model` - AI model inference requests
- `GET /v1/bedrock/models` - List available Commercial models
- `GET /v1/dashboard/requests` - Request audit logs and metrics

### 🧪 Test Coverage

- ✅ Cross-partition connectivity and authentication
- ✅ Claude 4.1 inference via inference profiles
- ✅ Claude 3.5 Sonnet direct model access
- ✅ Model discovery API functionality
- ✅ Dashboard API for logs and metrics
- ✅ Error handling and retry logic
- ✅ CloudWatch logging and DynamoDB audit trails

### 📚 Documentation Files

- `README.md` - Quick start guide and system overview
- `ARCHITECTURE.md` - Detailed technical architecture
- `create-comprehensive-bedrock-api-key.md` - API key setup guide
- `aws-profile-guide.md` - AWS CLI configuration
- `bedrock-enhanced-policy.json` - IAM policy template
- Component-specific READMEs in `infrastructure/` and `lambda/` directories

### 🚀 Deployment

- **Automated Deployment**: `./deploy-mvp.sh` for complete system setup
- **Manual Deployment**: Step-by-step infrastructure and Lambda deployment
- **Validation Scripts**: Comprehensive testing suite for deployment verification

### 🔮 Future Roadmap

- **Phase 2**: Enhanced Security & Governance (VPC endpoints, PrivateLink)
- **Phase 3**: Advanced Networking (VPN, Direct Connect)
- **Phase 4**: Enterprise Features (Multi-region, HA, multi-tenant)
- **Phase 5**: Advanced AI/ML Features (Fine-tuning, custom models)

### 📋 Requirements

#### Commercial AWS Account
- Bedrock model access enabled
- Enhanced IAM policy with inference profile permissions
- API key generation capability
- Models available in us-east-1

#### GovCloud Account
- API Gateway and Lambda permissions
- Secrets Manager access
- DynamoDB table creation
- Internet connectivity for HTTPS to Commercial AWS

---

**Release Notes**: This "Over the Internet" version establishes the foundation for secure cross-partition AI inference using public internet connectivity. Future versions will add enhanced networking options including VPC endpoints and private connectivity.