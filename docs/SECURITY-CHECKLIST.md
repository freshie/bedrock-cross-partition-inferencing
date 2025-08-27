# Security Checklist

## ⚠️ CRITICAL: Preventing Credential Exposure

This checklist helps prevent accidental exposure of AWS credentials and other sensitive data.

## Pre-Commit Checklist

### ✅ Before Every Commit:

1. **Scan for AWS Credentials**:
   ```bash
   # Check for AWS Access Keys
   grep -r "AKIA[0-9A-Z]{16}" .
   
   # Check for AWS Secret Keys (base64 patterns)
   grep -r "[A-Za-z0-9+/]{40,}={0,2}" . --exclude-dir=.git
   
   # Check for common secret patterns
   grep -ri "secret.*key\|api.*key\|password\|token" . --exclude-dir=.git
   ```

2. **Review Files Being Committed**:
   ```bash
   git diff --cached --name-only
   git diff --cached
   ```

3. **Check for Sensitive File Names**:
   - `*key*`, `*secret*`, `*credential*`, `*config*`
   - `.env`, `.aws/credentials`, `secrets.json`

### ✅ Repository Setup:

1. **Install git-secrets** (recommended):
   ```bash
   # macOS
   brew install git-secrets
   
   # Configure for this repo
   git secrets --install
   git secrets --register-aws
   ```

2. **Add .gitignore entries**:
   ```
   # AWS Credentials
   .aws/credentials
   .aws/config
   *.pem
   *.key
   
   # Environment files
   .env
   .env.local
   .env.production
   
   # Config files that might contain secrets
   config.json
   secrets.json
   *-config.json
   ```

## Incident Response

### If Credentials Are Exposed:

1. **IMMEDIATE (within minutes)**:
   - [ ] Revoke/disable the exposed credentials in AWS Console
   - [ ] Change any passwords or rotate keys
   - [ ] Remove sensitive data from current files

2. **SHORT TERM (within hours)**:
   - [ ] Clean git history using `git filter-branch` or `git filter-repo`
   - [ ] Force push cleaned history to all remotes
   - [ ] Notify team members to re-clone repository
   - [ ] Create new credentials with minimal required permissions

3. **FOLLOW UP (within days)**:
   - [ ] Audit all AWS CloudTrail logs for unauthorized access
   - [ ] Review and update security policies
   - [ ] Implement additional monitoring/alerting
   - [ ] Document lessons learned

## AWS Security Best Practices

### ✅ Credential Management:

1. **Use AWS Secrets Manager** for all application secrets
2. **Use IAM Roles** instead of access keys when possible
3. **Implement least privilege** - minimal required permissions only
4. **Rotate credentials regularly** - set calendar reminders
5. **Monitor credential usage** - set up CloudTrail alerts

### ✅ Code Security:

1. **Never hardcode credentials** in source code
2. **Use environment variables** for configuration
3. **Validate all inputs** to prevent injection attacks
4. **Implement proper error handling** - don't expose sensitive info in errors
5. **Use HTTPS/TLS** for all communications

### ✅ Repository Security:

1. **Make repositories private** when they contain business logic
2. **Review all contributors** and their access levels
3. **Enable branch protection** on main branches
4. **Require code reviews** for all changes
5. **Use signed commits** when possible

## Monitoring and Alerting

### Set up alerts for:

- New IAM users or access keys created
- Unusual API activity patterns
- Failed authentication attempts
- Access from unexpected IP addresses/regions
- High-volume API calls

### Regular Security Reviews:

- [ ] Monthly: Review IAM users and permissions
- [ ] Quarterly: Rotate all access keys and passwords
- [ ] Annually: Complete security audit and penetration testing

## Emergency Contacts

- **AWS Support**: [Your AWS Support Case URL]
- **Security Team**: [Your security team contact]
- **On-call Engineer**: [Your on-call contact]

---

## Tools and Resources

### Recommended Tools:
- [git-secrets](https://github.com/awslabs/git-secrets) - Prevents committing secrets
- [truffleHog](https://github.com/trufflesecurity/truffleHog) - Searches for secrets in git history
- [AWS Config](https://aws.amazon.com/config/) - Monitors AWS resource configurations
- [AWS GuardDuty](https://aws.amazon.com/guardduty/) - Threat detection service

### AWS Documentation:
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/)

---

**Remember: Security is everyone's responsibility. When in doubt, ask the security team!**