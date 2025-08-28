# Project Structure

This document describes the organization and purpose of files and directories in this repository.

## 📁 **Root Directory Structure**

```
cross-partition-inferencing/
├── 📁 .github/                    # GitHub workflows and templates
├── 📁 .kiro/                      # Kiro IDE specifications and settings
├── 📁 config/                     # Configuration files and examples
├── 📁 docs/                       # Documentation files
├── 📁 infrastructure/             # CloudFormation templates
├── 📁 lambda/                     # Lambda function source code
├── 📁 monitoring/                 # Monitoring and dashboard templates
├── 📁 outputs/                    # Generated output files from deployments
├── 📁 runbooks/                   # Operational runbooks and scripts
├── 📁 scripts/                    # Deployment and testing scripts
├── 📁 tests/                      # Test suites and test utilities
├── 📄 README.md                   # Main project documentation
├── 📄 ARCHITECTURE.md             # System architecture documentation
├── 📄 CHANGELOG.md                # Version history and changes
└── 📄 VERSION                     # Current version number
```

## 📚 **Key Documentation Files**

| File | Purpose |
|------|---------|
| `README.md` | Main project overview and quick start guide |
| `ARCHITECTURE.md` | Detailed system architecture and design decisions |
| `CHANGELOG.md` | Version history and release notes |
| `CURRENT-STATE-v1.3.0.md` | Current system state and deployment status |
| `docs/release-notes/` | Release notes for all versions |
| `SECURITY-APPROVAL.md` | Security review and approval documentation |

## 🏗️ **Infrastructure Components**

### **CloudFormation Templates** (`infrastructure/`)
- `dual-routing-api-gateway.yaml` - API Gateway configuration
- `dual-routing-auth.yaml` - Authentication and authorization
- `dual-routing-monitoring.yaml` - CloudWatch monitoring setup
- `dual-routing-vpn-infrastructure.yaml` - VPN infrastructure
- `dual-routing-vpn-lambda.yaml` - VPN Lambda configuration

### **Lambda Functions** (`lambda/`)
- `dual_routing_internet_lambda.py` - Internet routing handler
- `dual_routing_vpn_lambda.py` - VPN routing handler
- `dual_routing_authorizer.py` - Custom authorizer
- `dual_routing_error_handler.py` - Error handling utilities
- `dual_routing_metrics_processor.py` - Metrics processing

## 🔧 **Scripts and Automation** (`scripts/`)

### **Deployment Scripts**
- `deploy-dual-routing-api-gateway.sh` - Deploy API Gateway
- `deploy-dual-routing-auth.sh` - Deploy authentication
- `deploy-dual-routing-monitoring.sh` - Deploy monitoring
- `deploy-complete-vpn-infrastructure.sh` - Complete VPN deployment

### **Testing Scripts**
- `test-dual-routing-endpoints.sh` - Test API endpoints
- `test-dual-routing-auth.sh` - Test authentication
- `test-vpn-connectivity.sh` - Test VPN connectivity
- `run-comprehensive-validation.sh` - Full system validation

### **Security Scripts**
- `final-security-check.sh` - Critical security validation
- `production-security-scan.sh` - Production security scan
- `git-history-security-scan.sh` - Git history security check

### **Utility Scripts**
- `cleanup-project.sh` - Clean temporary files and artifacts
- `package-lambda-functions.sh` - Package Lambda deployments
- `validate-vpn-connectivity.sh` - VPN connectivity validation

## 🧪 **Testing Framework** (`tests/`)

### **Test Categories**
- `test_*_unit.py` - Unit tests for individual components
- `test_*_integration.py` - Integration tests
- `test_end_to_end_*.py` - End-to-end system tests
- `run_*_tests.py` - Test runners and utilities

### **Test Results**
- `results/` - Test execution results and reports
- `requirements.txt` - Testing dependencies

## 📊 **Monitoring and Operations**

### **Monitoring** (`monitoring/`)
- `vpn-dashboard-template.json` - CloudWatch dashboard template

### **Runbooks** (`runbooks/`)
- `incident-response.sh` - Incident response procedures
- `performance-monitoring.sh` - Performance monitoring scripts

### **Outputs** (`outputs/`)
- Generated reports from deployments and tests
- Security scan results
- VPN connectivity reports
- See `outputs/README.md` for details

## 🔒 **Security and Compliance**

### **Security Documentation**
- `docs/security-checklist.md` - Security validation checklist
- `SECURITY-APPROVAL.md` - Official security approval
- `GIT-HISTORY-SECURITY-ASSESSMENT.md` - Git history security review

### **Configuration Management** (`config/`)
- `config.example.sh` - Shell configuration template
- `config.sh` - Generated configuration (git-ignored)
- `config-vpn-example.sh` - VPN-specific configuration template
- `bedrock/` - Bedrock configuration files and IAM policies
  - `bedrock-api-key-config.json` - Example API key structure
  - `bedrock-full-access-policy.json` - IAM policy template
  - `README.md` - Bedrock configuration documentation
- `vpn-tunnels/` - VPN tunnel configuration files
- Security scanning scripts ensure no credentials are exposed

## 📚 **Documentation Directory** (`docs/`)

### **Release Documentation**
- `docs/release-notes/` - All version release notes
  - `RELEASE_NOTES_v1.4.0.md` - Enterprise Direct Connect Release
  - `RELEASE-NOTES-v1.3.2.md` - Autofix Release notes
  - `RELEASE-NOTES-v1.3.1.md` - Repository Cleanup Release notes
  - `RELEASE-NOTES-v1.3.0.md` - Security Enhanced Release notes

### **Setup and Configuration**
- `SETUP_GUIDE.md` - Complete setup instructions
- `aws-profile-guide.md` - AWS profile configuration
- `SETUP_COMMERCIAL_CREDENTIALS.md` - Commercial AWS setup

### **VPN Documentation**
- `VPN-Deployment-Guide.md` - VPN deployment instructions
- `VPN-Configuration-Management.md` - VPN configuration management
- `VPN-Operations-Guide.md` - VPN operations and maintenance
- `VPN-Troubleshooting-Guide.md` - VPN troubleshooting procedures
- `vpn-deployment-status-report.md` - Current VPN deployment status
- `vpn-testing-comparison.md` - VPN testing results and comparisons
- `vpn-tunnel-setup-guide.md` - VPN tunnel setup instructions

### **Technical Documentation**
- `TECHNICAL_SUMMARY.md` - Technical overview and architecture
- `Network-Architecture-Diagrams.md` - Network architecture diagrams
- `VPC-Endpoint-Configuration.md` - VPC endpoint configuration
- `Migration-Guide.md` - Migration procedures and guidelines

### **Security Documentation**
- `SECURITY-CHECKLIST.md` - Security validation checklist

## 🎯 **Development Workflow**

### **Kiro IDE Integration** (`.kiro/`)
- `specs/` - Feature specifications and requirements
- `settings/` - IDE configuration and preferences

### **GitHub Integration** (`.github/`)
- Workflow templates for CI/CD
- Issue and pull request templates
- Community health files

## 📋 **File Naming Conventions**

### **Scripts**
- `deploy-*.sh` - Deployment scripts
- `test-*.sh` - Testing scripts
- `validate-*.sh` - Validation scripts

### **Infrastructure**
- `dual-routing-*.yaml` - CloudFormation templates
- `*-infrastructure.yaml` - Infrastructure components
- `*-monitoring.yaml` - Monitoring configurations

### **Lambda Functions**
- `dual_routing_*.py` - Core routing functions
- `*_lambda.py` - Lambda function handlers
- `*_processor.py` - Processing utilities

### **Documentation**
- `*.md` - Markdown documentation
- `UPPERCASE.md` - Major documentation files
- `lowercase.md` - Specific guides and references

## 🧹 **Maintenance**

### **Regular Cleanup**
Run `./scripts/cleanup-project.sh` to remove:
- Temporary files and build artifacts
- Old test results and logs
- Python cache files
- Editor backup files

### **Version Management**
- `VERSION` file contains current version
- `CHANGELOG.md` tracks all changes
- Git tags mark official releases

## 🔍 **Finding Files**

### **Quick Reference**
- **Need to deploy?** → `scripts/deploy-*.sh`
- **Need to test?** → `scripts/test-*.sh`
- **Need documentation?** → `docs/` or `*.md` files
- **Need infrastructure?** → `infrastructure/*.yaml`
- **Need Lambda code?** → `lambda/*.py`
- **Need monitoring?** → `monitoring/` and `runbooks/`

### **Search Tips**
```bash
# Find all deployment scripts
find scripts/ -name "deploy-*.sh"

# Find all CloudFormation templates
find infrastructure/ -name "*.yaml"

# Find all test files
find . -name "test_*.py" -o -name "test-*.sh"

# Find documentation
find . -name "*.md" | grep -v node_modules
```