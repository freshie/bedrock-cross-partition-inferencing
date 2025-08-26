# AWS Profile Usage Guide

## Available Profiles

### Default Profile (Commercial AWS)
- **Profile Name**: `default`
- **Region**: us-east-1
- **Use Case**: Commercial AWS services and resources

### GovCloud Profile
- **Profile Name**: `govcloud`
- **Region**: us-gov-west-1
- **Use Case**: AWS GovCloud services and resources

## When to Use Each Profile

### Use `default` profile for:
- Commercial AWS workloads
- Standard AWS services in commercial regions
- Development and testing in commercial cloud
- Any non-government related AWS resources

### Use `govcloud` profile for:
- AWS GovCloud workloads
- Government compliance requirements
- Resources that need to be in GovCloud regions
- Any government-related AWS resources

## How to Use Profiles

### Using Default Profile
```bash
# These commands use the default profile automatically
aws s3 ls
aws ec2 describe-instances
aws sts get-caller-identity
```

### Using GovCloud Profile
```bash
# Add --profile govcloud to any AWS CLI command
aws s3 ls --profile govcloud
aws ec2 describe-instances --profile govcloud
aws sts get-caller-identity --profile govcloud
```

### Setting Environment Variable
```bash
# Set profile for current session
export AWS_PROFILE=govcloud

# Now all commands use govcloud profile
aws s3 ls
aws ec2 describe-instances
```

## Quick Reference

| Environment | Profile | Command Example |
|-------------|---------|-----------------|
| Commercial AWS | `default` | `aws s3 ls` |
| AWS GovCloud | `govcloud` | `aws s3 ls --profile govcloud` |

## Profile Configuration Files

- **Credentials**: `~/.aws/credentials`
- **Configuration**: `~/.aws/config`

Both profiles are properly configured and ready to use.