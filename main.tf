provider "aws" {
  region = var.aws_region
}

// Create Lambda functions from Docker
module "lambda_function" {
  source = "terraform-aws-modules/lambda/aws"

  // Runtime settings
  memory_size = 256
  timeout = 3
  runtime = "python3.8"
  package_type = "Zip"
  function_name = var.stack_name

  // Lambda source code
  source_path = "./lambda"
  handler = "app.lambda_handler"
  publish = true

  // Enable X-Ray tracing
  attach_tracing_policy = true
  tracing_mode = "Active"
  attach_cloudwatch_logs_policy = true

  allowed_triggers = {
    AllowAPIGateway = {
      service = "apigateway"
      source_arn = aws_api_gateway_rest_api.api.execution_arn
    }
  }

  layers = ["arn:aws:lambda:${var.aws_region}:580247275435:layer:LambdaInsightsExtension:14"]
  attach_policy = true
  policy        = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// Lambda IAM permission
resource "aws_lambda_permission" "aws_lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_function.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

// Create API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "terraform-lambda-api"
}

// Create /invoke path on API Gateway
resource "aws_api_gateway_resource" "resource" {
  path_part   = "{proxy+}"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

// Create ANY method
resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

// Create API Gateway integration
resource "aws_api_gateway_integration" "api" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.lambda_function.lambda_function_invoke_arn
}

resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name = "prod"

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}
