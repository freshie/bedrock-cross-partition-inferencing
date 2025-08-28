# Contributing to Cross-Partition Bedrock Inference Proxy

🎉 Thank you for your interest in contributing! This project enables AWS GovCloud applications to access Commercial Bedrock models securely.

## 🚀 **Quick Start for Contributors**

1. **Fork** the repository
2. **Clone** your fork locally
3. **Create** a feature branch: `git checkout -b feature/amazing-feature`
4. **Make** your changes
5. **Test** your changes thoroughly
6. **Commit** with clear messages: `git commit -m "✨ Add amazing feature"`
7. **Push** to your branch: `git push origin feature/amazing-feature`
8. **Open** a Pull Request

## 🎯 **Ways to Contribute**

### 🐛 **Bug Reports**
- Use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.md)
- Include steps to reproduce
- Provide CloudFormation stack outputs
- Include relevant logs (sanitized)

### ✨ **Feature Requests**
- Use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md)
- Explain the use case
- Consider security implications
- Suggest implementation approach

### 📖 **Documentation**
- Fix typos and improve clarity
- Add usage examples
- Update architecture diagrams
- Translate to other languages

### 🔧 **Code Contributions**
- Follow existing code style
- Add tests for new features
- Update documentation
- Ensure security best practices

## 🛡️ **Security Guidelines**

- **Never commit** real AWS credentials
- **Sanitize** all logs and examples
- **Follow** least-privilege principles
- **Test** security controls thoroughly

## 🧪 **Testing Requirements**

Before submitting:
- [ ] Run `./test-with-mock-key.sh` (mock testing)
- [ ] Test CloudFormation deployment
- [ ] Verify all documentation links
- [ ] Check for sensitive data in commits

## 📝 **Commit Message Guidelines**

Use conventional commits with emojis:
- `✨ feat: add new feature`
- `🐛 fix: resolve bug`
- `📖 docs: update documentation`
- `🔧 refactor: improve code structure`
- `🧪 test: add or update tests`
- `🔒 security: security improvements`

## 🏗️ **Development Setup**

```bash
# Clone your fork
git clone https://github.com/YOUR-USERNAME/bedrock-cross-partition-inferencing.git
cd bedrock-cross-partition-inferencing

# Set up AWS profiles (see aws-profile-guide.md)
aws configure --profile govcloud
aws configure --profile commercial

# Test the setup
./validate-setup.sh
```

## 🎯 **Priority Areas**

We especially welcome contributions in:
- 🔐 **Security enhancements**
- 📊 **Monitoring and observability**
- 🌐 **Multi-region support**
- 🧪 **Additional test coverage**
- 📖 **Documentation improvements**

## ❓ **Questions?**

- 💬 [Start a Discussion](https://github.com/freshie/bedrock-cross-partition-inferencing/discussions)
- 📧 Create an issue with the "question" label
- 📖 Check existing documentation

## 🙏 **Recognition**

All contributors will be recognized in our [Contributors section](README.md#contributors) and release notes.

---

**Happy Contributing!** 🚀