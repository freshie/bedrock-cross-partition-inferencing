# Cross-Partition Bedrock Inference Proxy

🚀 **Enable AWS GovCloud applications to access Commercial Bedrock models through a secure, compliant proxy**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS](https://img.shields.io/badge/AWS-GovCloud%20%2B%20Commercial-orange)](https://aws.amazon.com/)
[![Bedrock](https://img.shields.io/badge/Amazon-Bedrock-blue)](https://aws.amazon.com/bedrock/)
[![Version](https://img.shields.io/badge/Version-1.0.0%20Over%20Internet-green)](https://github.com/freshie/bedrock-cross-partition-inferencing/releases)

## 🎯 **The Challenge: Bridging the AI Gap**

Government agencies and regulated industries operating in AWS GovCloud face a critical challenge: accessing the latest AI models available in AWS Commercial partition. While AWS GovCloud provides essential security and compliance features, it has limited availability of generative AI services like Amazon Bedrock compared to the commercial partition.

**Key Challenges:**
- 🚫 **Limited AI Model Availability**: Fewer Amazon Bedrock models in GovCloud
- ⏰ **Delayed Rollouts**: New AI services arrive later in GovCloud
- 🔒 **Compliance Requirements**: Must maintain strict data governance
- 🚀 **Innovation Constraints**: Slower adoption affects mission-critical applications

**This solution bridges that gap securely**, enabling access to cutting-edge models like Claude 4.1, Nova Premier, and Llama 4 while maintaining compliance.

## 🏗️ **Architecture Overview: Three Implementation Options**

This solution provides three architectural approaches, allowing organizations to choose based on their security requirements, performance needs, and implementation timeline.

### 🚀 **Current Implementation: Option 1 - Over the Internet (v1.0.0)**

*This is the MVP approach currently implemented in this repository*

![Cross-Partition Inference Architecture - Over Internet](docs/images/cross-partition-inference-architecture-over-internet.drawio.png)

The internet-based approach provides the fastest path to cross-partition AI access using HTTPS connections over the public internet, prioritizing speed of implementation while maintaining essential security controls.

**Architecture Flow:**
1. **GovCloud applications** send requests to API Gateway for authentication and routing
2. **Lambda function** acts as a cross-partition proxy, retrieving credentials from Secrets Manager  
3. **HTTPS calls** to Amazon Bedrock in the commercial partition over the public internet
4. **Comprehensive logging** through CloudWatch for audit and monitoring requirements

### 🔮 **Future Options (Roadmap)**

#### Option 2: Site-to-Site VPN (v2.0.0 - Planned)
![Cross-Partition Inference Architecture - VPN](docs/images/cross-partition-inference-architecture-vpn.drawio.png)

Enhanced security through encrypted tunnels between AWS partitions with private subnet deployment and VPC endpoints.

#### Option 3: AWS Direct Connect (v3.0.0 - Planned)  
![Cross-Partition Inference Architecture - Direct Connect](docs/images/cross-partition-inference-architecture-direct-connect.drawio.png)

Enterprise-grade solution with dedicated private network connections for maximum performance and security.

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

## 🗺️ **Implementation Roadmap**

We recommend a three-phase implementation strategy that allows organizations to start quickly while building toward enterprise-grade capabilities:

### Phase 1: MVP Deployment ✅ **CURRENT** 
**v1.0.0 "Over the Internet" (Weeks 1-4)**
- ✅ Basic cross-partition AI access using internet-based architecture
- ✅ Validate functionality and gather initial performance metrics
- ✅ **Rapid Implementation**: Can be deployed in 1-2 weeks
- ✅ **Cost Effective**: Minimal infrastructure with pay-per-use model

### Phase 2: VPN Enhancement 🔄 **PLANNED**
**v2.0.0 "Site-to-Site VPN" (Weeks 5-12)**
- 🔄 Implement Site-to-Site VPN architecture
- 🔄 Improve security and performance for production workloads
- 🔄 **Enhanced Security**: All traffic through private, encrypted tunnels
- 🔄 **Production Ready**: Suitable for consistent performance needs

### Phase 3: Direct Connect Optimization 📋 **FUTURE**
**v3.0.0 "AWS Direct Connect" (Weeks 13-32)**
- 📋 Deploy Direct Connect infrastructure
- 📋 Highest-volume, most critical applications
- 📋 **Maximum Performance**: High bandwidth, low-latency connections
- 📋 **Enterprise Scale**: Supports high-volume AI inference applications

## 🎯 **Benefits of Cross-Partition AI Implementation**

**🚀 Access to Cutting-Edge AI**: Immediate access to latest AI models (Claude 4.1, Nova Premier, Llama 4) while maintaining compliance posture

**🔒 Maintained Compliance**: All data handling meets government security standards through comprehensive encryption, network isolation, and audit logging

**⚡ Operational Efficiency**: Unified management experience across partitions using familiar AWS tools and services

**💰 Cost Optimization**: Access commercial partition capabilities without duplicating infrastructure

**🔬 Innovation Enablement**: Rapidly adopt new AI capabilities as they become available while meeting security obligations

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

## 📖 **Background: Unlocking Commercial AI Models in AWS GovCloud**

This project addresses a critical challenge faced by government agencies and regulated industries: accessing the latest AI models while operating within AWS GovCloud's security and compliance boundaries. 

**The Problem**: Digital transformation initiatives across government agencies increasingly rely on AI, but AWS GovCloud has limited availability of generative AI services compared to the commercial partition. This creates barriers to AI innovation for organizations that must operate within strict compliance boundaries.

**Our Solution**: A comprehensive cross-partition AI inference architecture that enables GovCloud applications to securely access Amazon Bedrock services in the AWS Commercial partition while maintaining data sovereignty and meeting all compliance requirements.

For a detailed analysis of the challenges, solution approaches, and implementation strategy, see our comprehensive blog post: [Unlocking Commercial AI Models in AWS GovCloud: Secure Cross-Partition Access for Government Workloads](cross-partition-ai-inference-blog.md)

## ⚠️ **Disclaimer**

This is an educational/demonstration project showcasing cross-partition AI inference patterns. For production use:
- Review security requirements with your security team
- Implement additional monitoring and alerting  
- Consider compliance requirements (FedRAMP, etc.)
- Test thoroughly in your environment
- Validate against your organization's data governance policies

## 🆘 **Support**

- 📖 [Documentation](./docs/)
- 🐛 [Issues](https://github.com/freshie/bedrock-cross-partition-inferencing/issues)
- 💬 [Discussions](https://github.com/freshie/bedrock-cross-partition-inferencing/discussions)

---

**Built with ❤️ for the AWS community**