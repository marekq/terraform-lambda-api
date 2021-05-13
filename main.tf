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
    RestApiGateway = {
      service = "apigateway"
      source_arn = aws_api_gateway_rest_api.api.execution_arn
    },
    HttpApiGateway = {
      service = "apigateway"
      source_arn = module.api_gateway.apigatewayv2_api_arn
    }
  }

  layers = ["arn:aws:lambda:${var.aws_region}:580247275435:layer:LambdaInsightsExtension:14"]
  attach_policy = true
  policy        = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

// REST API - Lambda IAM permission
resource "aws_lambda_permission" "rest_api_permission" {
  statement_id  = "rest_api_permission"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_function.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

resource "aws_lambda_permission" "http_api_permission" {
  statement_id  = "http_api_permission"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_function.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.api_gateway.apigatewayv2_api_execution_arn}/*/*/*"
}


///////////////////////////////////

// Create REST API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name = "terraform-lambda-api-rest"
  description = "terraform-lambda-api-rest"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

// Create proxy path on REST API Gateway
resource "aws_api_gateway_resource" "resource" {
  path_part   = "{proxy+}"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

// Create ANY method
resource "aws_api_gateway_method" "method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.resource.id
  http_method   = "GET"
  authorization = "NONE"
}

// Create API Gateway Lambda Proxy integration
resource "aws_api_gateway_integration" "api" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = module.lambda_function.lambda_function_invoke_arn
}

// Create API Gateway deployment
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

// Create API Gateway stage "prod"
resource "aws_api_gateway_stage" "prod" {
  deployment_id         = aws_api_gateway_deployment.api.id
  rest_api_id           = aws_api_gateway_rest_api.api.id
  stage_name            = "prod"
  xray_tracing_enabled  = true
}

///////////////////////////////////

// Create HTTP API Gateway
module "api_gateway" {
  source = "terraform-aws-modules/apigateway-v2/aws"

  name = "terraform-lambda-api-http"
  description = "terraform-lambda-api-http"
  protocol_type = "HTTP"
  create_api_domain_name = false

  default_route_settings = {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 100
    throttling_rate_limit    = 100
  }

  integrations = {
    "GET /{proxy+}" = {
      lambda_arn = module.lambda_function.lambda_function_arn
    }

    "$default" = {
      lambda_arn = module.lambda_function.lambda_function_arn
    }
  }
}
