provider "aws" {
  region = "eu-west-2"
}


#source
data "archive_file" "zip" {
  type        = "zip"
  source_file = "main"
  output_path = "hello.zip"
}

#lambda
resource "aws_lambda_function" "hello" {
  function_name    = "hello"
  filename         = "hello.zip"
  handler          = "main"
  source_code_hash = "data.archive_file.zip.output_base64sha256"
  role             = aws_iam_role.iam_for_lambda.arn
  runtime          = "go1.x"
  memory_size      = 128
  timeout          = 10
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "hello_lambda"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
}
EOF
}

#api gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "hello_api"
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "hello"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "POST"
  authorization = "AWS_IAM"
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

resource "aws_api_gateway_deployment" "hello_deploy" {
  depends_on  = [aws_api_gateway_integration.integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "v1"
  triggers = {
    redeployment = sha1(join(",", list(
      jsonencode(aws_api_gateway_integration.integration),
    )))
  }
  lifecycle {
    create_before_destroy = true
  }
}

#cognito
resource "aws_cognito_user_pool" "hello" {
  name                = "hello cognito pool"
  username_attributes = ["email"]
  username_configuration {
    case_sensitive = false
  }
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "nickname"
    required                 = false
    string_attribute_constraints {
      max_length = "2048"
      min_length = "0"
    }
  }
  password_policy {
    minimum_length                   = "8"
    require_lowercase                = false
    require_uppercase                = false
    require_numbers                  = false
    require_symbols                  = false
    temporary_password_validity_days = 7
  }
  mfa_configuration        = "OFF"
  auto_verified_attributes = ["email"]
  verification_message_template {
    default_email_option  = "CONFIRM_WITH_LINK"
    email_message_by_link = "Confirm your account {##Click Here##}"
    email_subject_by_link = "Welcome to Hello app"
  }
  email_configuration {
    email_sending_account  = "COGNITO_DEFAULT"
    reply_to_email_address = "hello@test.com"
  }
  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }
  tags = {}
}

resource "aws_cognito_user_pool_domain" "hello" {
  user_pool_id = aws_cognito_user_pool.hello.id
  domain       = "hello-test-12345"
}

resource "aws_cognito_user_pool_client" "hello" {
  user_pool_id                 = aws_cognito_user_pool.hello.id
  name                         = "hello-app-client"
  refresh_token_validity       = 30
  read_attributes              = ["nickname"]
  write_attributes             = ["nickname"]
  supported_identity_providers = ["COGNITO"]
  callback_urls                = ["http://localhost:3000"]
  logout_urls                  = ["http://localhost:3000"]
}

resource "aws_cognito_identity_pool" "hello" {
  identity_pool_name               = "hello app"
  allow_unauthenticated_identities = false
  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.hello.id
    provider_name           = aws_cognito_user_pool.hello.endpoint
    server_side_token_check = false
  }
}

resource "aws_cognito_identity_pool_roles_attachment" "hello" {
  identity_pool_id = aws_cognito_identity_pool.hello.id
  roles = {
    "authenticated"   = aws_iam_role.api_gateway_access.arn
    "unauthenticated" = aws_iam_role.deny_everything.arn
  }
}

resource "aws_iam_role_policy" "api_gateway_access" {
  name   = "api-gateway-acess"
  role   = aws_iam_role.api_gateway_access.id
  policy = data.aws_iam_policy_document.api_gateway_access.json
}

resource "aws_iam_role" "api_gateway_access" {
  name               = "ap-gateway-access"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "${aws_cognito_identity_pool.hello.id}"
        },
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "authenticated"
        }
      }
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "api_gateway_access" {
  version = "2012-10-17"
  statement {
    actions = [
      "execute-api:Invoke"
    ]
    effect    = "Allow"
    resources = ["arn:aws:execute-api:*:*:*"]
  }
}

resource "aws_iam_role_policy" "deny_everything" {
  name   = "deny_everything"
  role   = aws_iam_role.deny_everything.id
  policy = data.aws_iam_policy_document.deny_everything.json
}

resource "aws_iam_role" "deny_everything" {
  name = "deny_everything"
  # This will grant the role the ability for cognito identity to assume it
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "${aws_cognito_identity_pool.hello.id}"
        },
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "unauthenticated"
        }
      }
    }
  ]
}
EOF
}

data "aws_iam_policy_document" "deny_everything" {
  version = "2012-10-17"
  statement {
    actions   = ["*"]
    effect    = "Deny"
    resources = ["*"]
  }
}


#output
output "url" {
  value = "${aws_api_gateway_deployment.hello_deploy.invoke_url}${aws_api_gateway_resource.resource.path}"
}

output "user_pool_id" {
  value = aws_cognito_user_pool.hello.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.hello.id
}

output "identity_pool_id" {
  value = aws_cognito_identity_pool.hello.id
}
