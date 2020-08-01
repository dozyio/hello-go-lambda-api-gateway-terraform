provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

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

data "archive_file" "dlq_consumer_zip" {
  type        = "zip"
  source_file = "${var.lambdaspath}/dlq-consumer/main"
  output_path = "${var.lambdaspath}/dlq-consumer/dlq-consumer.zip"
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
  // vars for SQS come from SSM parameter store at runtime
  // enable / disable SSM cache from environment vars
  environment {
    variables = {
      "USE_SSM_CACHE"     = "TRUE"
      "SSM_CACHE_TIMEOUT" = "300"
    }
  }
  dead_letter_config {
    target_arn = aws_sns_topic.dlq_topic.arn
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
  environment {
    variables = {
      "USE_SSM_CACHE"     = "TRUE"
      "SSM_CACHE_TIMEOUT" = "300"
      "ALWAYS_ERROR"      = "FALSE" //for testing dead letter queue
    }
  }
}

resource "aws_lambda_function" "dlq_consumer" {
  function_name                  = "dlq_consumer"
  filename                       = "${var.lambdaspath}/dlq-consumer/dlq-consumer.zip"
  handler                        = "main"
  source_code_hash               = filebase64sha256(data.archive_file.dlq_consumer_zip.output_path)
  role                           = aws_iam_role.iam_for_dlq_consumer_lambda.arn
  runtime                        = "go1.x"
  memory_size                    = 128
  timeout                        = 10
  reserved_concurrent_executions = 5
  environment {
    variables = {
      "USE_SSM_CACHE"     = "TRUE"
      "SSM_CACHE_TIMEOUT" = "300"
    }
  }
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

resource "aws_iam_role" "iam_for_dlq_consumer_lambda" {
  name = "dlq_consumer_lambda"
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
resource "aws_cloudwatch_log_group" "hello" {
  name              = "/aws/lambda/${aws_lambda_function.hello.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "sqs_consumer" {
  name              = "/aws/lambda/${aws_lambda_function.sqs_consumer.function_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "dlq_consumer" {
  name              = "/aws/lambda/${aws_lambda_function.dlq_consumer.function_name}"
  retention_in_days = 7
}


#SQS
resource "aws_sqs_queue" "hello_queue" {
  name_prefix                = "hello_"
  delay_seconds              = 0
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  max_message_size           = 2048
  fifo_queue                 = false
  receive_wait_time_seconds  = 10
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 4
  })
}

resource "aws_sqs_queue" "dlq" {
  name_prefix                = "dlq_"
  delay_seconds              = 0
  visibility_timeout_seconds = 60
  message_retention_seconds  = 345600 //4 days
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

resource "aws_iam_role_policy_attachment" "dlq_consumer" {
  policy_arn = aws_iam_policy.dlq_consumer.arn
  role       = aws_iam_role.iam_for_dlq_consumer_lambda.name
}

resource "aws_iam_policy" "hello" {
  policy = data.aws_iam_policy_document.hello.json
}

resource "aws_iam_policy" "sqs_consumer" {
  policy = data.aws_iam_policy_document.sqs_consumer.json
}

resource "aws_iam_policy" "dlq_consumer" {
  policy = data.aws_iam_policy_document.dlq_consumer.json
}


data "aws_iam_policy_document" "hello" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = ["arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    actions = [
      "sqs:SendMessage"
    ]
  }

  statement {
    sid       = "AllowWritingLogs"
    effect    = "Allow"
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*:*"]
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }
}

data "aws_iam_policy_document" "sqs_consumer" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = ["arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
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
    resources = ["arn:aws:lambda:${var.region}:${data.aws_caller_identity.current.account_id}:function:*"]
    actions   = ["lambda:InvokeFunction"]
  }

  statement {
    sid       = "AllowWritingLogs"
    effect    = "Allow"
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*:*"]
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

data "aws_iam_policy_document" "dlq_consumer" {
  statement {
    sid       = "AllowSQSPermissions"
    effect    = "Allow"
    resources = ["arn:aws:sqs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    actions = [
      "sqs:ChangeMessageVisibility",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "AllowWritingLogs"
    effect    = "Allow"
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*:*"]
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }
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

resource "aws_lambda_permission" "allow_dlq_to_lambda" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dlq_consumer.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.dlq.arn
}

resource "aws_lambda_event_source_mapping" "event_source_mapping_dlq_to_lambda" {
  batch_size       = 1
  event_source_arn = aws_sqs_queue.dlq.arn
  enabled          = true
  function_name    = aws_lambda_function.dlq_consumer.arn
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
    resources = ["arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
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


#DynamoDB
resource "aws_dynamodb_table" "hello" {
  name           = "hello"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "pkey"
  range_key      = "skey"

  global_secondary_index {
    name = "gsi1"
    //swap hash & range key for secondary index
    hash_key        = "skey"
    range_key       = "pkey"
    write_capacity  = 5
    read_capacity   = 5
    projection_type = "ALL"
  }

  stream_enabled = false
  //stream_view_type = "NEW_IMAGE"
  //stream_view_type = ""

  server_side_encryption {
    enabled = false
  }

  point_in_time_recovery {
    enabled = false
  }

  attribute {
    name = "pkey"
    type = "S"
  }

  attribute {
    name = "skey"
    type = "S"
  }
}


resource "aws_iam_role_policy_attachment" "sqs_lambda_dynamodb" {
  policy_arn = aws_iam_policy.sqs_lambda_dynamodb.arn
  role       = aws_iam_role.iam_for_sqs_consumer_lambda.name
}

resource "aws_iam_policy" "sqs_lambda_dynamodb" {
  policy = data.aws_iam_policy_document.sqs_lambda_dynamodb.json
}

data "aws_iam_policy_document" "sqs_lambda_dynamodb" {
  statement {
    sid    = "ListAndDescribe"
    effect = "Allow"
    actions = [
      "dynamodb:List*",
      "dynamodb:DescribeReservedCapacity*",
      "dynamodb:DescribeLimits",
      "dynamodb:DescribeTimeToLive",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "SpecificTable"
    effect    = "Allow"
    resources = ["arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.hello.name}"]
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeStream",
      "dynamodb:DescribeTable",
      "dynamodb:Get*",
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
    ]
  }
}


#SNS
resource "aws_sns_topic" "dlq_topic" {
  name = "dlq-topic"
}

resource "aws_iam_role_policy_attachment" "dlq_lambda" {
  policy_arn = aws_iam_policy.dlq.arn
  role       = aws_iam_role.iam_for_dlq_consumer_lambda.name
}

resource "aws_iam_policy" "dlq" {
  policy = data.aws_iam_policy_document.dlq.json
}

data "aws_iam_policy_document" "dlq" {
  statement {
    sid    = "Publish"
    effect = "Allow"
    actions = [
      "SNS:Publish",
    ]
    resources = [aws_sns_topic.dlq_topic.arn]
  }
}


#Systems Manager - parameter store
resource "aws_ssm_parameter" "project_region" {
  name      = "project_region"
  type      = "String"
  value     = var.region
  overwrite = true
}

resource "aws_ssm_parameter" "cognito_region" {
  name      = "cognito_region"
  type      = "String"
  value     = var.region
  overwrite = true
}

resource "aws_ssm_parameter" "user_pools_id" {
  name      = "user_pools_id"
  type      = "String"
  value     = aws_cognito_user_pool.hello.id
  overwrite = true
}

resource "aws_ssm_parameter" "user_pools_web_client_id" {
  name      = "user_pools_web_client_id"
  type      = "String"
  value     = aws_cognito_user_pool_client.hello.id
  overwrite = true
}

resource "aws_ssm_parameter" "cognito_identity_pool_id" {
  name      = "cognito_identity_pool"
  type      = "String"
  value     = aws_cognito_identity_pool.hello.id
  overwrite = true
}

resource "aws_ssm_parameter" "gateway_endpoint" {
  name      = "gateway_endpoint"
  type      = "String"
  value     = "${aws_api_gateway_deployment.hello_deploy.invoke_url}${aws_api_gateway_resource.resource.path}"
  overwrite = true
}

resource "aws_ssm_parameter" "sqs_arn" {
  name      = "sqs_arn"
  type      = "String"
  value     = aws_sqs_queue.hello_queue.arn
  overwrite = true
}

resource "aws_ssm_parameter" "sqs_url" {
  name      = "sqs_url"
  type      = "String"
  value     = aws_sqs_queue.hello_queue.id
  overwrite = true
}

resource "aws_ssm_parameter" "dynamodb_arn" {
  name      = "dynamodb_arn"
  type      = "String"
  value     = aws_dynamodb_table.hello.arn
  overwrite = true
}

resource "aws_ssm_parameter" "dynamodb_id" {
  name      = "dynamodb_id"
  type      = "String"
  value     = aws_dynamodb_table.hello.id
  overwrite = true
}

resource "aws_ssm_parameter" "dynamodb_table_name" {
  name      = "dynamodb_table_name"
  type      = "String"
  value     = aws_dynamodb_table.hello.name
  overwrite = true
}

resource "aws_ssm_parameter" "dlq_topic_arn" {
  name      = "dlq_topic_arn"
  type      = "String"
  value     = aws_sns_topic.dlq_topic.arn
  overwrite = true
}

/*
resource "aws_ssm_parameter" "dynamodb_stream_arn" {
  name      = "dynamodb_stream_arn"
  type      = "String"
  value     = aws_dynamodb_table.hello.stream_arn
  overwrite = true
}

resource "aws_ssm_parameter" "dynamodb_stream_label" {
  name      = "dynamodb_stream_label"
  type      = "String"
  value     = aws_dynamodb_table.hello.stream_label
  overwrite = true
}
*/

resource "aws_iam_role_policy_attachment" "hello_ssm" {
  policy_arn = aws_iam_policy.hello_ssm.arn
  role       = aws_iam_role.iam_for_hello_lambda.name
}

resource "aws_iam_role_policy_attachment" "sqs_consumer_ssm" {
  policy_arn = aws_iam_policy.sqs_consumer_ssm.arn
  role       = aws_iam_role.iam_for_sqs_consumer_lambda.name
}

resource "aws_iam_role_policy_attachment" "dlq_consumer_ssm" {
  policy_arn = aws_iam_policy.dlq_consumer_ssm.arn
  role       = aws_iam_role.iam_for_dlq_consumer_lambda.name
}

resource "aws_iam_policy" "hello_ssm" {
  policy = data.aws_iam_policy_document.ssm_parameter_store.json
}

resource "aws_iam_policy" "sqs_consumer_ssm" {
  policy = data.aws_iam_policy_document.ssm_parameter_store.json
}

resource "aws_iam_policy" "dlq_consumer_ssm" {
  policy = data.aws_iam_policy_document.ssm_parameter_store.json
}

data "aws_iam_policy_document" "ssm_parameter_store" {
  statement {
    sid       = "DescribeParameters"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }
  statement {
    sid       = "AllowSSMPermissions"
    effect    = "Allow"
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/*"]
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
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
