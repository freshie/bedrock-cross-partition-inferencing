# Outputs Directory

This directory contains output files from various deployment and testing operations.

## 📁 **File Categories**

### **Security Scan Results**
- `git-history-security-*.txt` - Git history security scan results
- `security-scan-*.txt` - Security scan outputs

### **VPN Infrastructure Reports**
- `complete-vpn-infrastructure-summary-*.txt` - Complete VPN deployment summaries
- `vpc-endpoints-deployment-report-*.txt` - VPC endpoints deployment reports
- `vpn-connectivity-test-*.txt` - VPN connectivity test results
- `vpn-connectivity-validation-report-*.txt` - VPN validation reports
- `vpn-infrastructure-deployment-report-*.txt` - Infrastructure deployment reports
- `vpn-infrastructure-outputs.json` - CloudFormation outputs from VPN deployment
- `vpn-lambda-test-report-*.txt` - Lambda function test reports
- `vpn-tunnel-configuration-*.txt` - VPN tunnel configuration details

### **Status Reports**
- `vpn-deployment-status-report.md` - Current VPN deployment status

## 🧹 **Cleanup Policy**

These files are generated during deployment and testing operations. They can be safely removed if:
- The deployment/test was successful and no longer needed for reference
- The files are older than 30 days
- You need to free up space

## 📝 **File Naming Convention**

Files follow the pattern: `[operation-type]-[timestamp].txt`
- Timestamp format: `YYYYMMDD_HHMMSS`
- Example: `vpn-connectivity-test-20250827_220328.txt`

## 🔍 **Finding Recent Results**

To find the most recent results for a specific operation:
```bash
ls -la outputs/ | grep [operation-name] | tail -5
```

Example:
```bash
ls -la outputs/ | grep security-scan | tail -5
ls -la outputs/ | grep vpn-connectivity | tail -5
```