provider "aws" {
  region = var.region
}

#Source
data "archive_file" "hello_zip" {
  type        = "zip"
  source_file = "${var.lambdaspath}/hello/main"
  output_path = "${var.lambdaspath}/hello/hello.zip"
}


data "archive_file" "sqs_consumer_zip" {
  type        = "zip"
  source_file = "${var.lambdaspath}/sqs-consumer/main"
  output_path = "${var.lambdaspath}/sqs-consumer/sqs-consumer.zip"
}


#Lambda
resource "aws_lambda_function" "hello" {
  function_name                  = "hello"
  filename                       = "${var.lambdaspath}/hello/hello.zip"
  handler                        = "main"
  source_code_hash               = filebase64sha256(data.archive_file.hello_zip.output_path)
  role                           = aws_iam_role.iam_for_hello_lambda.arn
  runtime                        = "go1.x"
  memory_size                    = 128
  timeout                        = 10
  reserved_concurrent_executions = 5
  environment {
    variables = {
      "sqs_arn" = aws_sqs_queue.hello_queue.arn
      "sqs_url" = aws_sqs_queue.hello_queue.id
    }
  }
}

resource "aws_lambda_function" "sqs_consumer" {
  function_name                  = "sqs_consumer"
  filename                       = "${var.lambdaspath}/sqs-consumer/sqs-consumer.zip"
  handler                        = "main"
  source_code_hash               = filebase64sha256(data.archive_file.sqs_consumer_zip.output_path)
  role                           = aws_iam_role.iam_for_sqs_consumer_lambda.arn
  runtime                        = "go1.x"
  memory_size                    = 128
  timeout                        = 10
  reserved_concurrent_executions = 5
}

resource "aws_iam_role" "iam_for_hello_lambda" {
  name = "hello_lambda"
  lifecycle {
    create_before_destroy = true
  }
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

resource "aws_iam_role" "iam_for_sqs_consumer_lambda" {
  name = "sqs_consumer_lambda"
  lifecycle {
    create_before_destroy = true
  }
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

#Cloudwatch for lambdas
resource "aws_cloudwatch_log_group" "sqs_consumer" {
  name              = "/aws/lambda/${aws_lambda_function.sqs_consumer.function_name}"
  retention_in_days = 7
}
/*
resource "aws_cloudwatch_log_group" "hello" {
  name              = "/aws/lambda/${aws_lambda_function.hello.function_name}"
  retention_in_days = 7
}
*/

#SQS
resource "aws_sqs_queue" "hello_queue" {
  name_prefix                = "hello_"
  delay_seconds              = 0
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  max_message_size           = 2048
  fifo_queue                 = false
  receive_wait_time_seconds  = 10
}

resource "aws_iam_role_policy_attachment" "hello" {
  policy_arn = aws_iam_policy.hello.arn
  role       = aws_iam_role.iam_for_hello_lambda.name
}

resource "aws_iam_role_policy_attachment" "sqs_consumer" {
  policy_arn = aws_iam_policy.sqs_consumer.arn
  role       = aws_iam_role.iam_for_sqs_consumer_lambda.name
}

resource "aws_iam_policy" "hello" {
  policy = data.aws_iam_policy_document.hello.json
}

resource "aws_iam_policy" "sqs_consumer" {
  policy = data.aws_iam_policy_document.sqs_consumer.json
}

data "aws_iam_policy_document" "hello" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = ["arn:aws:sqs:*"]
    actions = [
      "sqs:SendMessage"
    ]
  }
}

data "aws_iam_policy_document" "sqs_consumer" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = ["arn:aws:sqs:*"]
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "AllowInvokingLambdas"
    effect    = "Allow"
    resources = ["arn:aws:lambda:*:*:function:*"]
    actions   = ["lambda:InvokeFunction"]
  }

  statement {
    sid       = "AllowWritingLogs"
    effect    = "Allow"
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/*:*"]
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }

  #don't create log groups here so terraform can manage them
  /*
  statement {
    sid       = "AllowCreatingLogGroups"
    effect    = "Allow"
    resources = ["arn:aws:logs:*:*:*"]
    actions   = ["logs:CreateLogGroup"]
  }
*/
}

resource "aws_lambda_permission" "allow_sqs_to_lambda" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sqs_consumer.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.hello_queue.arn
}

resource "aws_lambda_event_source_mapping" "event_source_mapping" {
  batch_size       = 1
  event_source_arn = aws_sqs_queue.hello_queue.arn
  enabled          = true
  function_name    = aws_lambda_function.sqs_consumer.arn
}

#API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "hello_api"
  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "hello"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_method" "method" {
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.resource.id
  http_method      = "POST"
  authorization    = "AWS_IAM"
  api_key_required = "false"
  request_parameters = {
    "method.request.path.hello" = true
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

resource "aws_api_gateway_integration_response" "response" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "POST"
  status_code = "200"
  depends_on = [
    aws_api_gateway_integration.integration
  ]
}

##API Gateway - Cors
resource "aws_api_gateway_method" "options" {
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.resource.id
  http_method      = "OPTIONS"
  authorization    = "NONE"
  api_key_required = "false"
}

resource "aws_api_gateway_method_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "OPTIONS"
  status_code = "200"
  #all false with terraformer
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers"     = "true"
    "method.response.header.Access-Control-Allow-Methods"     = "true"
    "method.response.header.Access-Control-Allow-Origin"      = "true"
    "method.response.header.Access-Control-Allow-Credentials" = "true"
  }
  response_models = {
    "application/json" = "Empty"
  }
  depends_on = [
    aws_api_gateway_method.options
  ]
}

resource "aws_api_gateway_integration" "options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "OPTIONS"
  type        = "MOCK"
  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
  depends_on = [
    aws_api_gateway_method.options
  ]
}
resource "aws_api_gateway_integration_response" "options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.resource.id
  http_method = "OPTIONS"
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'DELETE,GET,HEAD,OPTIONS,PATCH,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  #"method.response.header.Access-Control-Allow-Credentials" = "true"
  depends_on = [
    aws_api_gateway_integration.options
  ]
}

##API Gateway Lamda
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

##API Gateway Deploy
resource "aws_api_gateway_deployment" "hello_deploy" {
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
  depends_on = [
    aws_api_gateway_integration.integration
  ]
}


#Cognito
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
    name                     = "email"
    required                 = true
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
  /*
  verification_message_template {
    default_email_option  = "CONFIRM_WITH_LINK"
    email_message_by_link = "Confirm your account {##Click Here##}"
    email_subject_by_link = "Welcome to Hello app"
  }
  */
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  email_verification_subject = "Your Hello App verification code"
  email_verification_message = "Your verification code is {####}"
  sms_verification_message   = "Your verification code is {####}"
  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }
  tags = {
    name = "hello"
  }
}

resource "aws_cognito_user_pool_domain" "hello" {
  user_pool_id = aws_cognito_user_pool.hello.id
  domain       = "hello-test-12345"
}

resource "aws_cognito_user_pool_client" "hello" {
  user_pool_id                 = aws_cognito_user_pool.hello.id
  name                         = "hello-app-client"
  refresh_token_validity       = 30
  supported_identity_providers = ["COGNITO"]
  callback_urls                = ["http://localhost:8080"]
  logout_urls                  = ["http://localhost:8080"]
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
  name   = "api-gateway-access"
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
output "aws_project_region" {
  value = var.region
}
output "aws_cognito_region" {
  value = var.region
}
output "aws_user_pools_id" {
  value = aws_cognito_user_pool.hello.id
}
output "aws_user_pools_web_client_id" {
  value = aws_cognito_user_pool_client.hello.id
}
output "aws_cognito_identity_pool_id" {
  value = aws_cognito_identity_pool.hello.id
}
output "gateway_endpoint" {
  value = "${aws_api_gateway_deployment.hello_deploy.invoke_url}${aws_api_gateway_resource.resource.path}"
}
