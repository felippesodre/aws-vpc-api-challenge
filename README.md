# AWS VPC API Challenge

## Challenge Overview

**Objective**  
Create an API based on AWS services that can create a VPC with multiple subnets and store the results.  
We need to be able to retrieve the data of created resources from the API.  

- Code should be written in **Python**  
- The API should be protected with an **authentication layer**  
- Authorization should be open to all authenticated users  

**Outcome**  
Document the exercise (code, config files, README) in a GitHub (or similar) repository and share it with us at least one day before the demo.  

**Bonus**  
Automate the setup as much as possible using AWS serverless services.  

---

## Features

- Create, retrieve, and delete AWS VPCs and subnets via API.  
- Authentication with AWS Cognito.  
- Infrastructure as Code with Terraform.  
- Serverless deployment: AWS Lambda + API Gateway.  
- Public callback page hosted on S3 for Cognito OAuth flow.  

---

## Prerequisites

Before starting, ensure the following tools are installed and configured:

- **AWS CLI** with credentials. Requires permissions for VPC, S3, Lambda, Cognito, API Gateway, IAM.
```sh
aws configure
```
- **Terraform** >= 1.10
- **curl** (for API testing)
- **jq** (optional, for JSON parsing)
- **Postman** (optional, for API testing)
---

## Repository Structure
```text
aws-vpc-api-challenge
├── README.md
├── .gitignore
├── lambda
│   ├── deployment.zip
│   ├── lambda_function.py
│   └── requirements.txt
└── terraform
    ├── callback_page.tf
    ├── locals.tf
    ├── main.tf
    ├── outputs.tf
    ├── template
    │   └── callback.html.tmpl
    ├── terraform.tfvars
    ├── variables.tf
    ├── versions.tf
```

---

## Lambda Function

### Overview
The Lambda function manages AWS VPCs and subnets. It is triggered by API Gateway and supports creating, listing, retrieving, and deleting VPCs and their subnets. All metadata is stored in DynamoDB.

### Usage
- The Lambda function is triggered by API Gateway HTTP requests.
- Supported HTTP methods: GET, POST, DELETE.

### Code Logic
- **GET**: If `vpc_id` is provided in query parameters, retrieves a specific VPC from DynamoDB. If not, lists all VPCs.
- **POST**: Creates a new VPC and subnets in AWS using parameters from the request body. Saves details in DynamoDB. Prevents duplicate VPCs with the same CIDR.
- **DELETE**: If `vpc_id` is provided, deletes the specified VPC and its subnets from AWS and DynamoDB. If not, deletes all VPCs and subnets.
- Handles errors and returns appropriate HTTP status codes and messages. All operations are logged for troubleshooting.

---

## Resources

- **DynamoDB Table**: Stores VPC and Subnets metadata.
- **IAM Roles & Policies**: Permissions for Lambda execution and access to AWS resources.
- **Lambda Function**: Python function to manage VPCs and Subnets via API.
- **API Gateway (HTTP)**: Exposes the Lambda through protected HTTP endpoints.
- **Cognito User Pool & Client**: User authentication via JWT.
- **Cognito User Pool Domain**: Domain for Cognito authentication.
- **Cognito Users**: Users created in the User Pool.
- **S3 Bucket (callback)**: Stores the callback page for authentication (referenced in callback/logout URLs).

---

## About the State File

- The state file (`terraform.tfstate`) is configured to be stored locally.
- **Note:** In production environments, it is recommended to use a [Remote State](https://www.terraform.io/language/state/remote) (e.g., S3) to ensure security, integrity, and collaboration.

---

## Relevant Information

- The provisioning creates all resources needed for authentication, authorization, and VPC management via API.
- Cognito protects API Gateway endpoints using JWT.
- You cannot exchange the authorization code for the token twice. It´s required to authenticate again on Cognito to generate a new code and exchange it.
- The authorization code expres in 5 minutos and the token 60 minutos.
- Lambda performs CRUD operations on VPCs and logs information in DynamoDB.
- The S3 bucket serves the callback page for OAuth authentication.
- IAM permissions are restricted to the necessary resources.

---

## Step-by-Step Usage

### 1. Clone the Repository
```sh
git clone https://github.com/felippesodre/aws-vpc-api-challenge.git
cd aws-vpc-api-challenge/terraform
```

### 2. Configure Variables
Edit `terraform.tfvars` to set your `cognito_users`, `project_name`, `region`:
```hcl
cognito_users = ["your-email@example.com"] # Emails will receive username + temporary password
project_name  = "challenge"
region        = "us-east-1"
```

### 3. Initialize Terraform
```sh
terraform init
```

### 4. Review the Plan
```sh
terraform plan
```

### 5. Apply the Infrastructure
```sh
terraform apply
```
Confirm when prompted. After deployment, check Terraform outputs for your API endpoint and Cognito URL.

### 6. First Login with Cognito

Open the Cognito URL from the Terraform outputs.
Log in with the temporary credentials sent to your email.
Change your password when prompted.
After login, you’ll be redirected to the static callback page (S3).
On the callback page, you’ll find the command to exchange the authorization code for a token.

### 7. Lambda Packaging (if updating code)
If you change the Lambda code, repackage it:
```sh
cd ../lambda
zip deployment.zip lambda_function.py
# Add dependencies if needed:
# pip install -r requirements.txt -t .
# zip -r deployment.zip .
```
After packaging, re-run `terraform apply` to update the Lambda deployment.

---

### API Usage Examples

All requests require a valid Cognito JWT token in the `Authorization` header. See Cognito documentation or project instructions for authentication steps.
The `API_ENDPOINT` with your deployed API endpoint will be available after `terraform apply` in the outputs. You must export it as an environment variable:
```sh
export API_ENDPOINT="<your-api-endpoint>"
```
For the token, use the `COGNITO_TOKEN` environment variable you get after Cognito authentication on step 6.

#### Create VPC and Subnets (POST /vpc)
You must provide the VPC and Subnets data. You can create one VPC with multiple subnets.
```sh
curl -X POST $API_ENDPOINT \
    -H "Authorization: Bearer $COGNITO_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
        "vpc_cidr": "10.0.0.0/16",
        "vpc_tags": [{"Key": "Name", "Value": "TestVPC"}],
        "subnets": [
            {"cidr": "10.0.1.0/24", "az": "us-east-1a", "tags": [{"Key": "Name", "Value": "SubnetA"}]},
            {"cidr": "10.0.2.0/24", "az": "us-east-1b", "tags": [{"Key": "Name", "Value": "SubnetB"}]}
        ]
    }'
```

#### List All VPCs (GET /vpc)
```sh
curl -X GET $API_ENDPOINT \
    -H "Authorization: Bearer $COGNITO_TOKEN"
```

#### Get Specific VPC (GET /vpc?vpc_id=...)
```sh
curl -X GET "$API_ENDPOINT?vpc_id=<VPC_ID>" \
    -H "Authorization: Bearer $COGNITO_TOKEN"
```

#### Delete Specific VPC (DELETE /vpc?vpc_id=...)
```sh
curl -X DELETE "$API_ENDPOINT?vpc_id=<VPC_ID>" \
    -H "Authorization: Bearer $COGNITO_TOKEN"
```

#### Delete All VPCs (DELETE /vpc)
```sh
curl -X DELETE $API_ENDPOINT \
    -H "Authorization: Bearer $COGNITO_TOKEN"
```

---

## Resource Cleanup

To remove all provisioned resources:
```sh
terraform destroy
```
