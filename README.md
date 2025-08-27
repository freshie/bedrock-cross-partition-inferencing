# Cross-Partition Bedrock Inference Proxy

🚀 **Enable AWS GovCloud applications to access Commercial Bedrock models through a secure, compliant proxy**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS](https://img.shields.io/badge/AWS-GovCloud%20%2B%20Commercial-orange)](https://aws.amazon.com/)
[![Bedrock](https://img.shields.io/badge/Amazon-Bedrock-blue)](https://aws.amazon.com/bedrock/)

## 🎯 **What This Solves**

AWS GovCloud provides isolated infrastructure for sensitive workloads, but Amazon Bedrock's latest AI models (Claude 4.1, Nova Premier, Llama 4) are only available in Commercial AWS regions. This proxy bridges that gap securely.

## 🏗️ **Architecture**

```
┌─────────────────┐    HTTPS/TLS    ┌──────────────────┐    Bedrock API    ┌─────────────────┐
│   GovCloud      │ ──────────────► │  Commercial AWS  │ ─────────────────► │   Bedrock       │
│   Application   │                 │   API Gateway    │                    │   Models        │
└─────────────────┘                 └──────────────────┘                    └─────────────────┘
                                             │
                                             ▼
                                    ┌──────────────────┐
                                    │   Lambda Proxy   │
                                    │   + Secrets Mgr  │
                                    └──────────────────┘
```

## ✨ **Features**

- 🔐 **Secure**: API key authentication with AWS Secrets Manager
- 📊 **Monitored**: Complete audit logging to DynamoDB
- 🚀 **Fast**: Direct API Gateway to Lambda integration
- 🔄 **Reliable**: Automatic failover and error handling
- 📈 **Scalable**: Serverless architecture with auto-scaling
- 🛡️ **Compliant**: Designed for government and enterprise use

## 🚀 **Quick Start**

### Prerequisites
- AWS GovCloud account with appropriate permissions
- AWS Commercial account with Bedrock access
- AWS CLI configured for both partitions

### 1. Deploy the Infrastructure

```bash
# Clone the repository
git clone https://github.com/freshie/bedrock-cross-partition-inferencing.git
cd bedrock-cross-partition-inferencing

# Deploy to Commercial AWS (us-east-1)
./infrastructure/deploy.sh

# Note the API Gateway URL from the output
```

### 2. Configure Credentials

```bash
# Create Bedrock API key in Commercial AWS
aws iam create-service-specific-credential \
  --user-name bedrock-api-user \
  --service-name bedrock.amazonaws.com \
  --credential-age-days 365

# Store in Secrets Manager (done automatically by deployment)
```

### 3. Test the Proxy

```bash
# Test from GovCloud
./test-invoke-model.sh
```

## 📖 **Usage Examples**

### Python Client
```python
import requests
import json

# Your API Gateway endpoint
endpoint = "https://your-api-id.execute-api.us-east-1.amazonaws.com/v1"

# Invoke Claude 4.1
response = requests.post(f"{endpoint}/bedrock/invoke-model", 
    headers={"Content-Type": "application/json"},
    json={
        "modelId": "anthropic.claude-opus-4-1-20250805-v1:0",
        "body": {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "messages": [{"role": "user", "content": "Hello!"}]
        }
    }
)
```

### cURL
```bash
curl -X POST "https://your-api-id.execute-api.us-east-1.amazonaws.com/v1/bedrock/invoke-model" \
  -H "Content-Type: application/json" \
  -d '{
    "modelId": "amazon.nova-premier-v1:0",
    "body": {
      "messages": [{"role": "user", "content": "Explain quantum computing"}],
      "max_tokens": 500
    }
  }'
```

## 🗺️ **Roadmap**

- **v1.0** ✅ Internet connectivity (current)
- **v2.0** 🔄 VPN connectivity option
- **v3.0** 📋 AWS Direct Connect support

## 📁 **Project Structure**

```
├── infrastructure/          # CloudFormation templates
├── lambda/                 # Lambda function code
├── tests/                  # Test scripts
├── docs/                   # Documentation
└── .kiro/specs/           # Feature specifications
```

## 🔧 **Configuration**

### Environment Variables
- `SECRETS_ARN`: ARN of the Secrets Manager secret
- `LOG_LEVEL`: Logging level (INFO, DEBUG, ERROR)
- `REGION`: Target Bedrock region (default: us-east-1)

### Secrets Manager Format
```json
{
  "bedrock_api_key": "your-base64-encoded-api-key",
  "region": "us-east-1"
}
```

## 🛡️ **Security**

- All credentials stored in AWS Secrets Manager
- TLS encryption for all communications
- Complete audit logging to DynamoDB
- IAM-based access controls
- No sensitive data in logs or code

## 📊 **Monitoring**

- **CloudWatch Logs**: Lambda execution logs
- **DynamoDB**: Request/response audit trail
- **CloudWatch Metrics**: Performance and error metrics
- **X-Ray**: Distributed tracing (optional)

## 🤝 **Contributing**

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 **License**

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ **Disclaimer**

This is an educational/demonstration project. For production use:
- Review security requirements with your security team
- Implement additional monitoring and alerting
- Consider compliance requirements (FedRAMP, etc.)
- Test thoroughly in your environment

## 🆘 **Support**

- 📖 [Documentation](./docs/)
- 🐛 [Issues](https://github.com/freshie/bedrock-cross-partition-inferencing/issues)
- 💬 [Discussions](https://github.com/freshie/bedrock-cross-partition-inferencing/discussions)

---

**Built with ❤️ for the AWS community**