Generate an Amazon Bedrock API key
PDF
RSS
Focus mode
No results foundSummarize page

You can generate an Amazon Bedrock API key using either the AWS Management Console or the AWS API. We recommend that you use the AWS Management Console to easily generate an Amazon Bedrock API key with few steps.
Warning

We strongly recommend restricting the use of Amazon Bedrock API keys for exploration of Amazon Bedrock. When you're ready to incorporate Amazon Bedrock into applications with greater security requirements, you should switch to short-term credentials. For more information, see Alternatives to long-term access keys in the IAM User Guide.
Topics

    Generate an Amazon Bedrock API key using the console

    Generate a long-term Amazon Bedrock API key using the API

    Generate a short-term Amazon Bedrock API key using a client library

    Set up automatic refresh of short-term Amazon Bedrock API keys

Generate an Amazon Bedrock API key using the console

To generate an Amazon Bedrock API key using the console, do the following:

    Sign in to the AWS Management Console with an IAM principal that has permissions to use the Amazon Bedrock console. Then, open the Amazon Bedrock console at https://console.aws.amazon.com/bedrock/

.

In the left navigation pane, select API keys.

Generate one of the following types of keys:

    Short-term API key – In the Short-term API keys tab, choose Generate short-term API keys. The key expires when your console session expires (and no longer than 12 hours) and lets you make calls to the AWS Region that you generated it from. You can modify the Region directly in the generated key.

    Long-term API key – In the Long-term API keys tab, choose Generate long-term API keys.

        In the API key expiration section, choose a time after which the key will expire.

        (Optional) By default, the AmazonBedrockLimitedAccess AWS-managed policy, which grants access to core Amazon Bedrock API operations, is attached to the IAM user associated with the key. To select more policies to attach to the user, expand the Advanced permissions section and select the policies that you want to add.

        Choose Generate.

        Warning

        We strongly recommend restricting the use of Amazon Bedrock API keys for exploration of Amazon Bedrock. When you're ready to incorporate Amazon Bedrock into applications with greater security requirements, you should switch to short-term credentials. For more information, see Alternatives to long-term access keys in the IAM User Guide.

Generate a long-term Amazon Bedrock API key using the API

The general steps for creating a long-term Amazon Bedrock API key in the API are as follows:

    Create an IAM user by sending a CreateUser request with an IAM endpoint.

    Attach the AmazonBedrockLimitedAccess to the IAM user by sending an AttachUserPolicy request with an IAM endpoint. You can repeat this step to attach other managed or custom policies as necessary to the user.

    Note

    As a best security practice, we strongly recommend that you attach IAM policies to the IAM user to restrict the use of Amazon Bedrock API keys. For examples of time-bounding policies and restricting the IP addresses that can use the key, see Control the use of access keys by attaching an inline policy to an IAM user.

    Generate the long-term Amazon Bedrock API key by sending a CreateServiceSpecificCredential request with an IAM endpoint and specifying bedrock.amazonaws.com as the ServiceName.

        The ServiceApiKeyValue returned in the response is your long-term Amazon Bedrock API key.

        The ServiceSpecificCredentialId returned in the response can be used to carry out API operations related to the key.

To learn how to generate a long-term Amazon Bedrock API key, choose the tab for your preferred method, and then follow the steps:

To create a long-term Amazon Bedrock API key, you use AWS Identity and Access Management API operations. First, make sure that you've fulfilled the prerequisite:
Prerequisite

Ensure that your setup allows the AWS CLI to automatically recognize your AWS credentials. To learn more, see Configuring settings for the AWS CLI.

Open a terminal and run the following commands:

    Create an IAM user. You can replace the name with one of your choice:

aws iam create-user --user-name bedrock-api-user

Attach the AmazonBedrockLimitedAccess to the user. You can repeat this step with the ARNs of any other AWS-managed or custom policies you want to add to the API key:

aws iam attach-user-policy --user-name bedrock-api-user --policy-arn arn:aws:iam::aws:policy/AmazonBedrockLimitedAccess

Create the long-term Amazon Bedrock API key, replacing ${NUMBER-OF-DAYS} with the number of days for which you want the key to last:

    aws iam create-service-specific-credential \
        --user-name bedrock-api-user \
        --service-name bedrock.amazonaws.com \
        --credential-age-days ${NUMBER-OF-DAYS}

Generate a short-term Amazon Bedrock API key using a client library

Short term keys have the following properties:

    Valid for the shorter of the following values:

        12 hours

        The duration of the session generated by the IAM principal used to generate the key.

    Inherit the permissions attached to the principal used to generate the key.

    Can be used only in the AWS Region from which you generated it.

For long-running applications, the aws-bedrock-token-generator

client library can create new Amazon Bedrock short-term API keys as needed when credentials are refreshed. For more information, see Set up automatic refresh of short-term Amazon Bedrock API keys.
Prerequisites

    Ensure that the IAM principal that you use to generate the key is set up with the proper permissions to use Amazon Bedrock. For experimentation, you can attach the AWS-managed AmazonBedrockLimitedAccess policy to the principal. You can refer to the Security best practices in IAM for protecting your credentials.

    Ensure that your setup allows Python to automatically recognize your AWS credentials. The default method by which credentials are retrieved follows a defined hierarchy. You can see the hierarchy for a specific SDK or tool at AWS SDKs and Tools standardized credential providers.

    Install the Amazon Bedrock token generator. Choose the tab for your preferred method, and then follow the steps:

Open a terminal and run the following command:

pip install aws-bedrock-token-generator

Examples

To see examples for using the token generator to generate a short-term Amazon Bedrock API key with your default credentials in different languages, choose the tab for your preferred method, and then follow the steps:

from aws_bedrock_token_generator import provide_token

token = provide_token()
print(f"Token: {token}")

To see more examples for different use cases when generating tokens, see the following links:

    Python

Javascript

Java
Set up automatic refresh of short-term Amazon Bedrock API keys

You can create a script with the help of the aws-bedrock-token-generator package to programmatically regenerate a new short-term key whenever your current one has expired. First, ensure that you've fulfilled the prerequisites at Generate a short-term Amazon Bedrock API key using a client library. To see example scripts that retrieve a token and make a Converse request, choose the tab for your preferred method, and then follow the steps:

from aws_bedrock_token_generator import provide_token
import requests

def get_new_token():
    url = "https://bedrock-runtime.us-west-2.amazonaws.com/model/us.anthropic.claude-3-5-haiku-20241022-v1:0/converse"
    payload = {
        "messages": [
            {
                "role": "user",
                "content": [{"text": "Hello"}]
            }
        ]
    }

    # Create a token provider that uses default credentials and region providers.
    # You can configure it to use other credential providers.
    # https://github.com/aws/aws-bedrock-token-generator-python/blob/main/README.md
    # It can be used for each API call as it is inexpensive.
    token = provide_token()

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}"
    }

    response = requests.post(url, headers=headers, json=payload)
    print(response.json())

if __name__ == "__main__":
    get_new_token()