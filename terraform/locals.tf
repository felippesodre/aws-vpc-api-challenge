locals {
  cognito_domain = "https://${aws_cognito_user_pool_domain.this.domain}.auth.${var.region}.amazoncognito.com"
  callback_url   = "https://${aws_s3_bucket.callback.bucket}.s3.${var.region}.amazonaws.com/callback.html"
}
