# Development Guide

## Getting Started

This guide helps developers set up their environment and understand the development workflow for the Cross-Partition Bedrock Inference Proxy.

## Prerequisites

- AWS CLI configured with GovCloud credentials
- Node.js 18+ (for local development tools)
- Python 3.9+ (for Lambda function development)
- Git with Code Defender configured

## Development Environment Setup

### 1. Clone and Setup
```bash
git clone https://github.com/freshie/bedrock-cross-partition-inferencing.git
cd bedrock-cross-partition-inferencing

# Create your feature branch from develop
git checkout develop
git pull origin develop
git checkout -b feature/your-feature-name
```

### 2. Configuration
```bash
# Copy and configure your settings
cp config.example.sh config.sh
# Edit config.sh with your specific values

# Extract configuration from deployed stack (if available)
./scripts/get-config.sh
```

### 3. Local Testing
```bash
# Test the Lambda function locally
cd lambda
python -m pytest tests/

# Test API endpoints (requires deployed infrastructure)
./test-invoke-model.sh
./test-claude-4-1.sh
```

## Development Workflow

### Feature Development
1. **Start from develop**: Always branch from the latest `develop`
2. **Small commits**: Make focused, atomic commits
3. **Test thoroughly**: Run all tests before pushing
4. **Document changes**: Update relevant documentation
5. **Pull request**: Submit PR to `develop` branch

### Code Standards
- **Python**: Follow PEP 8 style guidelines
- **Shell scripts**: Use shellcheck for validation
- **Documentation**: Update README and relevant docs
- **Security**: Never commit sensitive information

### Testing Strategy
- **Unit tests**: Test individual functions
- **Integration tests**: Test API endpoints
- **Security tests**: Validate no secrets in commits
- **Performance tests**: Monitor response times

## Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GovCloud      │    │   API Gateway    │    │  Commercial     │
│   Application   │───▶│   + Lambda       │───▶│  Bedrock API    │
│                 │    │   (Proxy)        │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Key Components
- **API Gateway**: Receives requests from GovCloud applications
- **Lambda Function**: Processes and forwards requests to Commercial Bedrock
- **Secrets Manager**: Stores Bedrock API credentials securely
- **CloudFormation**: Infrastructure as Code deployment

## Common Development Tasks

### Adding a New Model
1. Update Lambda function with model-specific handling
2. Add test cases for the new model
3. Update documentation with model capabilities
4. Test end-to-end functionality

### Enhancing Error Handling
1. Identify error scenarios
2. Add appropriate error handling in Lambda
3. Update CloudWatch logging
4. Test error conditions

### Performance Optimization
1. Profile current performance
2. Identify bottlenecks
3. Implement optimizations
4. Validate improvements with tests

## Debugging

### CloudWatch Logs
```bash
# View Lambda logs
aws logs tail /aws/lambda/cross-partition-inference --follow --profile govcloud
```

### Local Testing
```bash
# Test Lambda function locally
cd lambda
python lambda_function.py
```

### API Gateway Testing
```bash
# Direct API Gateway testing
aws apigateway test-invoke-method \
  --rest-api-id YOUR-API-ID \
  --resource-id YOUR-RESOURCE-ID \
  --http-method POST \
  --profile govcloud
```

## Release Process

### Preparing for Release
1. **Merge to develop**: Ensure all features are in `develop`
2. **Test thoroughly**: Run full test suite
3. **Update version**: Update VERSION file and CHANGELOG.md
4. **Documentation**: Ensure all docs are current

### Creating Release
1. **Merge to main**: `develop` → `main`
2. **Tag release**: `git tag -a v1.x.x -m "Release description"`
3. **Push**: `git push origin main --tags`
4. **GitHub release**: Create release notes on GitHub

## Troubleshooting

### Common Issues
- **Code Defender blocks**: Ensure repository is approved
- **API Gateway timeouts**: Check Lambda function performance
- **Authentication failures**: Verify Bedrock API keys
- **Cross-partition connectivity**: Check network configuration

### Getting Help
- Check existing [Issues](https://github.com/freshie/bedrock-cross-partition-inferencing/issues)
- Review [Documentation](docs/)
- Ask in [Discussions](https://github.com/freshie/bedrock-cross-partition-inferencing/discussions)

## Security Considerations

- Never commit API keys or sensitive information
- Use Secrets Manager for all credentials
- Follow AWS security best practices
- Regular security audits of dependencies
- Code Defender compliance for external repositories