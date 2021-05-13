output "rest_api_url" {
  value = join("", [aws_api_gateway_deployment.api.invoke_url, "/invoke"])
}

output "http_api_url" {
  value = join("", [module.api_gateway.default_apigatewayv2_stage_invoke_url, "invoke"])
}
