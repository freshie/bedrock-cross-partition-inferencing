# 🚨 EMERGENCY CREDENTIAL ROTATION CHECKLIST

## **IMMEDIATE ACTIONS - DO NOW**

### ✅ **Step 1: Disable/Rotate AWS Credentials**
- [ ] **URGENT**: Disable AWS user `bedrock-cross-partition-user`
- [ ] **URGENT**: Rotate Service Credential ID `ACCAQWPI74WHKCNQ4O7OM`
- [ ] **URGENT**: Revoke Bedrock API Key `ABSKYmVkcm9jay1jcm9zcy1wYXJ0aXRpb24tdXNlcisxLWF0LTA0ODI3MDE0MDgxNDpTL2NtVFlpcTF5dGd2dURocDNuOGUwcXVPZU9HUkk5ZFU4ajFlaEFuanhSUGh4Uy84TWpzYUxUV0U5WT0=`

### ✅ **Step 2: Monitor for Unauthorized Usage**
```bash
# Check AWS CloudTrail for suspicious activity
aws logs filter-log-events \
  --log-group-name CloudTrail/bedrock \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "bedrock-cross-partition-user"

# Monitor Bedrock API calls
aws logs filter-log-events \
  --log-group-name /aws/bedrock/inference \
  --start-time $(date -d '1 hour ago' +%s)000
```

### ✅ **Step 3: Generate New Credentials**
- [ ] Create new AWS user with minimal permissions
- [ ] Generate new Bedrock API key
- [ ] Update Secrets Manager with new credentials
- [ ] Test new credentials work properly

### ✅ **Step 4: Contact GitHub Support**
- [ ] Submit security request to GitHub: security@github.com
- [ ] Request immediate cache invalidation
- [ ] Provide commit hash: `a12f5138f2ca7b5cd5b2318971cba27b962bfc99`

---

## **AWS CLI Commands for Immediate Action**

### **Disable User**
```bash
# Disable the exposed user immediately
aws iam put-user-policy \
  --user-name bedrock-cross-partition-user \
  --policy-name DenyAllPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*"
    }]
  }'
```

### **List and Delete Access Keys**
```bash
# List access keys for the user
aws iam list-access-keys --user-name bedrock-cross-partition-user

# Delete all access keys (replace KEY_ID with actual key)
aws iam delete-access-key \
  --user-name bedrock-cross-partition-user \
  --access-key-id ACCAQWPI74WHKCNQ4O7OM
```

### **Monitor Recent Activity**
```bash
# Check recent API calls by this user
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=bedrock-cross-partition-user \
  --start-time $(date -d '24 hours ago' --iso-8601) \
  --end-time $(date --iso-8601)
```

---

## **GitHub Security Contact Information**

### **Primary Contact**
- **Email**: security@github.com
- **Subject**: "URGENT: Cached content with exposed AWS credentials"
- **Priority**: Critical/Immediate

### **Support Portal**
- **URL**: https://support.github.com/
- **Category**: Security Issue
- **Urgency**: Critical

### **Security Advisory**
- **URL**: https://github.com/contact/security
- **Type**: Credential Exposure
- **Impact**: High

---

## **Timeline**
- **T+0 minutes**: Disable AWS credentials (HIGHEST PRIORITY)
- **T+5 minutes**: Contact GitHub security
- **T+15 minutes**: Monitor for unauthorized usage
- **T+30 minutes**: Generate new credentials
- **T+60 minutes**: Update all systems with new credentials

**🚨 This is a critical security incident requiring immediate action! 🚨**