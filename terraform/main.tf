provider "aws" {
  region = var.region
}

# --- DynamoDB ---
resource "aws_dynamodb_table" "this" {
  name         = "${var.project_name}-vpc-metadata"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "vpc_id"

  attribute {
    name = "vpc_id"
    type = "S"
  }
}

# --- IAM ---
resource "aws_iam_role" "lambda" {
  name = "lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda" {
  name = "lambda_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:DescribeVpcs",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:DescribeSubnets",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Scan", "dynamodb:DeleteItem"]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.this.arn
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# --- Lambda Function ---
resource "aws_lambda_function" "vpc" {
  function_name    = "${var.project_name}-vpc-management"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda.arn
  filename         = "${path.module}/../lambda/deployment.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/deployment.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.this.name
    }
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.vpc.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.vpc.execution_arn}/${aws_apigatewayv2_stage.vpc.name}/*/*"
}

# --- API GATEWAY ---
resource "aws_apigatewayv2_api" "vpc" {
  name          = "${var.project_name}-vpc-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.vpc.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.vpc.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_stage" "vpc" {
  api_id      = aws_apigatewayv2_api.vpc.id
  name        = "dev"
  auto_deploy = true
}

resource "aws_apigatewayv2_route" "post_vpc" {
  api_id    = aws_apigatewayv2_api.vpc.id
  route_key = "POST /vpc"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "get_vpc" {
  api_id    = aws_apigatewayv2_api.vpc.id
  route_key = "GET /vpc"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_route" "delete_vpc" {
  api_id    = aws_apigatewayv2_api.vpc.id
  route_key = "DELETE /vpc"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  authorization_type = "JWT"
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  name             = "${var.project_name}-cognito-authorizer"
  api_id           = aws_apigatewayv2_api.vpc.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.this.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
  }
}

# --- COGNITO ---
resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-user-pool"
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 6
    require_lowercase = false
    require_numbers   = false
    require_symbols   = false
    require_uppercase = false
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name            = "${var.project_name}-app-client"
  user_pool_id    = aws_cognito_user_pool.this.id
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "profile", "email"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = [
    "https://${aws_s3_bucket.callback.bucket}.s3.${var.region}.amazonaws.com/callback.html"
  ]

  logout_urls = [
    "https://${aws_s3_bucket.callback.bucket}.s3.${var.region}.amazonaws.com/callback.html"
  ]
}

resource "aws_cognito_user_pool_domain" "this" {
  domain       = "${var.project_name}-auth-domain"
  user_pool_id = aws_cognito_user_pool.this.id
}

resource "aws_cognito_user" "this" {
  for_each = toset(var.cognito_users)

  user_pool_id = aws_cognito_user_pool.this.id
  username     = split("@", each.value)[0]

  attributes = {
    email          = each.key
    email_verified = true
  }
}
