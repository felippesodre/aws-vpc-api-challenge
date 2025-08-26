output "cognito_login_url" {
  description = "Cognito Hosted UI login URL"
  value = format(
    "https://%s.auth.%s.amazoncognito.com/login?client_id=%s&response_type=code&scope=email+openid+profile&redirect_uri=%s",
    aws_cognito_user_pool_domain.this.domain,
    var.region,
    aws_cognito_user_pool_client.this.id,
    urlencode("https://${aws_s3_bucket.callback.bucket}.s3.${var.region}.amazonaws.com/callback.html")
  )
}

output "api_endpoint" {
  value       = "${aws_apigatewayv2_api.vpc.api_endpoint}/${aws_apigatewayv2_stage.vpc.name}/vpc"
  description = "API endpoint URL"
}
