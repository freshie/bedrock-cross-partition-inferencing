# Scripts Reference Guide

This document provides a comprehensive overview of all scripts in the project, organized by category and highlighting the key testing scripts for cross-partition Bedrock access.

## 🎯 **Key Testing Scripts for Cross-Partition AI Access**

These are the primary scripts you'll use to test and validate cross-partition Bedrock functionality:

### 🌐 **Internet-Based Cross-Partition Testing (Option 1)**

**Primary Test Scripts:**
- **`scripts/test-claude-4-1.sh`** - Test Claude 4.1 model access over internet
- **`scripts/test-cross-partition.sh`** - Comprehensive cross-partition validation
- **`scripts/test-invoke-model.sh`** - Basic Bedrock model invocation test
- **`scripts/test-models-endpoint.sh`** - Test multiple model endpoints

**Usage Example:**
```bash
# Test Claude 4.1 specifically (most common use case)
./scripts/test-claude-4-1.sh

# Run comprehensive cross-partition tests
./scripts/test-cross-partition.sh

# Test basic model invocation
./scripts/test-invoke-model.sh
```

### 🔐 **VPN-Based Cross-Partition Testing (Option 2)**

**Primary Test Scripts:**
- **`scripts/test-vpn-comprehensive.sh`** - Complete VPN-based Bedrock testing
- **`scripts/test-vpn-lambda-integration.sh`** - VPN Lambda integration tests
- **`scripts/test-end-to-end-routing.sh`** - End-to-end routing validation
- **`scripts/validate-vpn-connectivity.sh`** - VPN connectivity validation

**Usage Example:**
```bash
# Test VPN-based Bedrock access (comprehensive)
./scripts/test-vpn-comprehensive.sh

# Test VPN Lambda integration
./scripts/test-vpn-lambda-integration.sh

# Validate VPN connectivity
./scripts/validate-vpn-connectivity.sh
```

## 📂 **Complete Scripts Inventory**

### 🚀 **Deployment Scripts**

| Script | Purpose | Usage |
|--------|---------|-------|
| `deploy-mvp.sh` | Deploy complete internet-based solution | `./deploy-mvp.sh` |
| `scripts/deploy-dual-routing-api-gateway.sh` | Deploy API Gateway for dual routing | Auto-called by other scripts |
| `scripts/deploy-dual-routing-auth.sh` | Deploy authentication components | Auto-called by other scripts |
| `scripts/deploy-dual-routing-monitoring.sh` | Deploy monitoring infrastructure | Auto-called by other scripts |
| `scripts/deploy-dual-routing-vpn-lambda.sh` | Deploy VPN Lambda functions | Auto-called by other scripts |
| `scripts/deploy-complete-vpn-infrastructure.sh` | Deploy complete VPN solution | `./scripts/deploy-complete-vpn-infrastructure.sh` |
| `scripts/deploy-vpc-endpoints.sh` | Deploy VPC endpoints | Auto-called by VPN deployment |
| `scripts/deploy-vpn-infrastructure.sh` | Deploy VPN infrastructure | Auto-called by complete deployment |

### 🧪 **Testing Scripts**

#### **Internet-Based Testing**
| Script | Purpose | Key Features |
|--------|---------|--------------|
| **`scripts/test-claude-4-1.sh`** | **Test Claude 4.1 access** | **Primary internet test** |
| **`scripts/test-cross-partition.sh`** | **Comprehensive validation** | **Full system test** |
| **`scripts/test-invoke-model.sh`** | **Basic model invocation** | **Quick validation** |
| `scripts/test-models-endpoint.sh` | Test multiple endpoints | Model compatibility check |
| `scripts/test-with-mock-key.sh` | Test with mock credentials | Development testing |
| `scripts/test-internet-lambda-unit.sh` | Unit test internet Lambda | Component testing |

#### **VPN-Based Testing**
| Script | Purpose | Key Features |
|--------|---------|--------------|
| **`scripts/test-vpn-comprehensive.sh`** | **Complete VPN testing** | **Primary VPN test** |
| **`scripts/test-vpn-lambda-integration.sh`** | **VPN Lambda integration** | **Core VPN functionality** |
| **`scripts/test-end-to-end-routing.sh`** | **End-to-end validation** | **Full routing test** |
| `scripts/test-vpn-lambda-unit.sh` | Unit test VPN Lambda | Component testing |
| `scripts/test-vpn-tunnel-connectivity.sh` | Test VPN tunnels | Network connectivity |
| `scripts/test-vpn-with-deployed-infrastructure.sh` | Test with deployed VPN | Infrastructure validation |

#### **Authentication & Security Testing**
| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/test-bearer-token-functionality.sh` | Test bearer token auth | Security validation |
| `scripts/test-lambda-bearer-token.sh` | Test Lambda token handling | Component security |
| `scripts/test-dual-routing-auth.sh` | Test dual routing auth | Authentication flow |
| `scripts/test-dual-routing-errors.sh` | Test error handling | Error scenarios |

### 🔧 **Configuration & Setup Scripts**

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/validate-setup.sh` | Validate initial setup | `./scripts/validate-setup.sh` |
| `scripts/get-config.sh` | Extract deployment config | `./scripts/get-config.sh` |
| `scripts/configure-vpn-tunnels.sh` | Configure VPN tunnels | Auto-called during VPN setup |
| `scripts/update-bearer-token-secret.sh` | Update authentication secrets | `./scripts/update-bearer-token-secret.sh` |

### 📊 **Monitoring & Performance Scripts**

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/create-monitoring-dashboard.sh` | Create CloudWatch dashboards | Auto-called during deployment |
| `scripts/test-monitoring-dashboard.sh` | Test monitoring setup | Validation script |
| `scripts/run-performance-comparison.sh` | Compare internet vs VPN performance | `./scripts/run-performance-comparison.sh` |
| `scripts/run-load-testing.sh` | Run load tests | Performance testing |
| `scripts/create-dual-routing-alarms.sh` | Create CloudWatch alarms | Auto-called during deployment |

### 🛡️ **Security & Validation Scripts**

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/security-scan.sh` | Run security scans | `./scripts/security-scan.sh` |
| `scripts/final-security-check.sh` | Final security validation | Pre-production check |
| `scripts/production-security-scan.sh` | Production security scan | Production validation |
| `scripts/git-history-security-scan.sh` | Scan git history for secrets | Security audit |
| `scripts/run-comprehensive-validation.sh` | Complete system validation | Full system check |

### 🔄 **Migration & Management Scripts**

| Script | Purpose | Usage |
|--------|---------|-------|
| `scripts/migrate-to-vpn.sh` | Migrate from internet to VPN | `./scripts/migrate-to-vpn.sh` |
| `scripts/rollback-to-internet.sh` | Rollback to internet-based | `./scripts/rollback-to-internet.sh` |
| `scripts/validate-migration.sh` | Validate migration success | Post-migration check |
| `scripts/cleanup-project.sh` | Clean up project resources | `./scripts/cleanup-project.sh` |

## 🎯 **Quick Start Testing Workflows**

### **Option 1: Internet-Based Testing (Recommended Start)**

```bash
# 1. Deploy the system
./deploy-mvp.sh

# 2. Validate setup
./scripts/validate-setup.sh

# 3. Test Claude 4.1 (primary use case)
./scripts/test-claude-4-1.sh

# 4. Run comprehensive tests
./scripts/test-cross-partition.sh
```

### **Option 2: VPN-Based Testing (Enhanced Security)**

```bash
# 1. Deploy VPN infrastructure
./scripts/deploy-complete-vpn-infrastructure.sh

# 2. Validate VPN connectivity
./scripts/validate-vpn-connectivity.sh

# 3. Test VPN-based Bedrock access
./scripts/test-vpn-comprehensive.sh

# 4. Test end-to-end routing
./scripts/test-end-to-end-routing.sh
```

## 🔍 **Script Categories by Use Case**

### **🚀 For Quick Validation**
- `scripts/test-claude-4-1.sh` - Test latest Claude model
- `scripts/test-invoke-model.sh` - Basic functionality check
- `scripts/validate-setup.sh` - Setup validation

### **🔬 For Comprehensive Testing**
- `scripts/test-cross-partition.sh` - Full internet-based testing
- `scripts/test-vpn-comprehensive.sh` - Full VPN-based testing
- `scripts/run-comprehensive-validation.sh` - Complete system validation

### **🛡️ For Security Validation**
- `scripts/security-scan.sh` - Security scanning
- `scripts/test-bearer-token-functionality.sh` - Authentication testing
- `scripts/final-security-check.sh` - Pre-production security check

### **📊 For Performance Analysis**
- `scripts/run-performance-comparison.sh` - Compare options
- `scripts/run-load-testing.sh` - Load testing
- `scripts/test-monitoring-dashboard.sh` - Monitoring validation

## 💡 **Best Practices**

1. **Start Simple**: Begin with `scripts/test-claude-4-1.sh` for quick validation
2. **Progress Systematically**: Use `scripts/test-cross-partition.sh` for comprehensive testing
3. **Security First**: Run `scripts/security-scan.sh` before production
4. **Monitor Performance**: Use `scripts/run-performance-comparison.sh` to compare options
5. **Validate Thoroughly**: Use `scripts/run-comprehensive-validation.sh` before deployment

## 🆘 **Troubleshooting**

If tests fail, check:
1. **Configuration**: Run `scripts/validate-setup.sh`
2. **Credentials**: Verify Secrets Manager configuration
3. **Network**: For VPN tests, check `scripts/validate-vpn-connectivity.sh`
4. **Logs**: Check CloudWatch logs for detailed error information

## 📝 **Script Naming Convention**

- `test-*` - Testing and validation scripts
- `deploy-*` - Deployment scripts
- `validate-*` - Validation and verification scripts
- `create-*` - Resource creation scripts
- `run-*` - Execution and orchestration scripts

---

**💡 Tip**: For most users, start with `scripts/test-claude-4-1.sh` to quickly validate cross-partition Bedrock access, then progress to `scripts/test-cross-partition.sh` for comprehensive testing.