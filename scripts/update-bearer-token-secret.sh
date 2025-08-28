#!/bin/bash

# Update Secrets Manager with Bedrock bearer token
# This script updates the commercial credentials secret to include the bearer token

set -e

# Default values
SECRET_NAME="cross-partition-commercial-creds"
GOVCLOUD_PROFILE="govcloud"
BEARER_TOKEN=""
UPDATE_EXISTING=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 --bearer-token <token> [--secret-name <name>] [--profile <profile>] [--update-existing]

This script updates AWS Secrets Manager with a Bedrock bearer token for cross-partition inference.

Options:
    --bearer-token <token>    The bearer token to store (required)
    --secret-name <name>      Name of the secret (default: cross-partition-commercial-creds)
    --profile <profile>       AWS profile to use (default: govcloud)
    --update-existing         Update existing secret instead of creating new one
    --help                    Show this help message

Examples:
    # Create new secret with bearer token
    $0 --bearer-token "YOUR_BEARER_TOKEN_HERE"

    # Update existing secret
    $0 --bearer-token "YOUR_BEARER_TOKEN_HERE" --update-existing

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --bearer-token)
            BEARER_TOKEN="$2"
            shift 2
            ;;
        --secret-name)
            SECRET_NAME="$2"
            shift 2
            ;;
        --profile)
            GOVCLOUD_PROFILE="$2"
            shift 2
            ;;
        --update-existing)
            UPDATE_EXISTING=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$BEARER_TOKEN" ]]; then
    echo "Error: Bearer token is required"
    usage
    exit 1
fi

# Function to check if secret exists
secret_exists() {
    aws secretsmanager describe-secret \
        --secret-id "$SECRET_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        >/dev/null 2>&1
}

# Function to create new secret
create_secret() {
    echo "Creating new secret: $SECRET_NAME"
    
    # Create the secret value JSON
    SECRET_VALUE=$(cat << EOF
{
    "bearer_token": "$BEARER_TOKEN",
    "created_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "description": "Bearer token for cross-partition Bedrock inference"
}
EOF
)

    aws secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --description "Cross-partition commercial credentials for Bedrock inference" \
        --secret-string "$SECRET_VALUE" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1

    echo "✅ Secret created successfully: $SECRET_NAME"
}

# Function to update existing secret
update_secret() {
    echo "Updating existing secret: $SECRET_NAME"
    
    # Get current secret value
    CURRENT_SECRET=$(aws secretsmanager get-secret-value \
        --secret-id "$SECRET_NAME" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1 \
        --query 'SecretString' \
        --output text)

    # Update the bearer token in the existing secret
    UPDATED_SECRET=$(echo "$CURRENT_SECRET" | jq --arg token "$BEARER_TOKEN" --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
        .bearer_token = $token |
        .updated_date = $date
    ')

    aws secretsmanager update-secret \
        --secret-id "$SECRET_NAME" \
        --secret-string "$UPDATED_SECRET" \
        --profile "$GOVCLOUD_PROFILE" \
        --region us-gov-west-1

    echo "✅ Secret updated successfully: $SECRET_NAME"
}

# Main execution
echo "🔐 Updating Secrets Manager with bearer token..."
echo "Secret Name: $SECRET_NAME"
echo "Profile: $GOVCLOUD_PROFILE"
echo "Region: us-gov-west-1"

# Check if secret exists and handle accordingly
if secret_exists; then
    if [[ "$UPDATE_EXISTING" == "true" ]]; then
        update_secret
    else
        echo "❌ Secret already exists: $SECRET_NAME"
        echo "Use --update-existing flag to update the existing secret"
        exit 1
    fi
else
    if [[ "$UPDATE_EXISTING" == "true" ]]; then
        echo "❌ Secret does not exist: $SECRET_NAME"
        echo "Remove --update-existing flag to create a new secret"
        exit 1
    else
        create_secret
    fi
fi

# Verify the secret was created/updated
echo "🔍 Verifying secret..."
aws secretsmanager describe-secret \
    --secret-id "$SECRET_NAME" \
    --profile "$GOVCLOUD_PROFILE" \
    --region us-gov-west-1 \
    --query '{Name: Name, Description: Description, LastChangedDate: LastChangedDate}' \
    --output table

echo "✅ Bearer token secret operation completed successfully!"
echo ""
echo "📋 Next steps:"
echo "1. Verify the secret contains the correct bearer token"
echo "2. Update your Lambda functions to use this secret"
echo "3. Test the cross-partition inference functionality"
echo ""
echo "🔍 To view the secret value:"
echo "aws secretsmanager get-secret-value --secret-id $SECRET_NAME --profile $GOVCLOUD_PROFILE --region us-gov-west-1"