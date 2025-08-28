# Contributing to Cross-Partition Bedrock Inference

Thank you for your interest in contributing to this project! This guide will help you get started.

## 🚀 Getting Started

### Prerequisites
- AWS CLI configured with appropriate permissions
- Basic understanding of AWS services (Lambda, API Gateway, CloudFormation)
- Familiarity with serverless architectures

### Development Setup
```bash
# Clone the repository
git clone https://github.com/freshie/bedrock-cross-partition-inferencing.git
cd cross-partition-inferencing

# Validate your environment
./scripts/validate-setup.sh

# Deploy for testing
./scripts/deploy-over-internet.sh
```

## 🤝 How to Contribute

### Reporting Issues
- Use GitHub Issues to report bugs or request features
- Provide detailed information including:
  - Steps to reproduce
  - Expected vs actual behavior
  - Environment details (AWS region, deployment type)
  - Relevant logs or error messages

### Suggesting Enhancements
- Check existing issues to avoid duplicates
- Clearly describe the enhancement and its benefits
- Consider backward compatibility
- Provide implementation suggestions if possible

### Code Contributions

#### 1. Fork and Branch
```bash
# Fork the repository on GitHub
# Clone your fork
git clone https://github.com/YOUR_USERNAME/bedrock-cross-partition-inferencing.git

# Create a feature branch
git checkout -b feature/your-feature-name
```

#### 2. Make Changes
- Follow existing code style and patterns
- Add tests for new functionality
- Update documentation as needed
- Ensure security best practices

#### 3. Test Your Changes
```bash
# Run validation tests
./scripts/validate-setup.sh

# Test your specific changes
./scripts/test-cross-partition.sh

# Run security scan
./scripts/security-scan.sh
```

#### 4. Submit Pull Request
- Create a clear PR description
- Reference related issues
- Include testing instructions
- Ensure CI checks pass

## 📋 Development Guidelines

### Code Style
- **Python**: Follow PEP 8 guidelines
- **Shell Scripts**: Use bash best practices
- **CloudFormation**: Use consistent naming and structure
- **Documentation**: Use clear, concise language

### Security Requirements
- Never commit credentials or sensitive data
- Use AWS Secrets Manager for all secrets
- Follow principle of least privilege for IAM roles
- Scan for security vulnerabilities before submitting

### Testing Standards
- Add unit tests for new Lambda functions
- Include integration tests for new features
- Test both internet and VPN deployment paths
- Validate error handling and edge cases

## 🏗️ Project Structure

### Key Directories
- `infrastructure/` - CloudFormation templates
- `lambda/` - Lambda function code
- `scripts/` - Deployment and testing scripts
- `docs/` - Documentation files
- `tests/` - Test suites and utilities

### Adding New Features

#### New Lambda Function
1. Create function in `lambda/` directory
2. Add CloudFormation template in `infrastructure/`
3. Create deployment script in `scripts/`
4. Add tests in `tests/` directory
5. Update documentation

#### New Deployment Option
1. Create CloudFormation template
2. Add deployment script
3. Create testing scripts
4. Update documentation and guides
5. Add to deployment options guide

#### New Documentation
1. Create in appropriate `docs/` subdirectory
2. Update main README if needed
3. Add to relevant guides and references
4. Ensure consistent formatting

## 🔧 Development Tools

### Useful Scripts
```bash
# Validate project setup
./scripts/validate-setup.sh

# Run comprehensive tests
./scripts/run-comprehensive-validation.sh

# Security scanning
./scripts/security-scan.sh

# Performance testing
./scripts/run-performance-comparison.sh
```

### Local Development
```bash
# Package Lambda functions locally
./scripts/package-lambda-functions.sh

# Test individual components
./scripts/test-api-gateway-integration.sh
./scripts/test-dual-routing-auth.sh
```

## 📚 Documentation Standards

### README Updates
- Keep main README concise and focused
- Move detailed content to appropriate docs
- Maintain consistent formatting
- Update table of contents if needed

### Code Documentation
- Add clear comments for complex logic
- Document function parameters and return values
- Include usage examples
- Explain security considerations

### Architecture Documentation
- Update architecture diagrams for significant changes
- Document design decisions and trade-offs
- Include performance and security implications
- Maintain consistency with implementation

## 🚨 Security Considerations

### Sensitive Data
- Never commit API keys, passwords, or credentials
- Use placeholder values in examples
- Scan git history for accidentally committed secrets
- Use `.gitignore` patterns to prevent accidents

### IAM Permissions
- Follow principle of least privilege
- Document required permissions
- Test with minimal permission sets
- Consider cross-account access patterns

### Network Security
- Validate VPN configurations
- Test network isolation
- Document security boundaries
- Consider compliance requirements

## 🔄 Release Process

### Version Management
- Follow semantic versioning (MAJOR.MINOR.PATCH)
- Update VERSION file for releases
- Tag releases in git
- Update CHANGELOG.md

### Testing Before Release
```bash
# Full system validation
./scripts/run-comprehensive-validation.sh

# Security validation
./scripts/final-security-check.sh

# Performance validation
./scripts/run-performance-comparison.sh
```

### Documentation Updates
- Update README if needed
- Add release notes to CHANGELOG.md
- Update version references
- Verify all links work

## 🤔 Questions?

### Getting Help
- Check existing documentation first
- Search GitHub Issues for similar questions
- Create a new issue with detailed information
- Join discussions in existing issues

### Community Guidelines
- Be respectful and constructive
- Help others when possible
- Share knowledge and experiences
- Follow the code of conduct

## 📄 License

By contributing to this project, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to Cross-Partition Bedrock Inference! Your contributions help make secure AI access available to more organizations.