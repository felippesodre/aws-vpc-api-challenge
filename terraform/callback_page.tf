# --- Bucket S3 for cognito callback ---
resource "aws_s3_bucket" "callback" {
  bucket = "${var.project_name}-callback"
}

resource "aws_s3_bucket_public_access_block" "callback" {
  bucket = aws_s3_bucket.callback.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_policy" {
  bucket = aws_s3_bucket.callback.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.callback.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "callback_page" {
  bucket = aws_s3_bucket.callback.id

  index_document {
    suffix = "callback.html"
  }
}

# --- Rendering HTML
data "template_file" "callback_html" {
  template = file("${path.module}/template/callback.html.tmpl")
  vars = {
    client_id      = aws_cognito_user_pool_client.this.id
    cognito_domain = local.cognito_domain
    redirect_uri   = local.callback_url
  }
}

# --- Uploading file
resource "aws_s3_object" "callback_html" {
  bucket       = aws_s3_bucket.callback.id
  key          = "callback.html"
  content      = data.template_file.callback_html.rendered
  content_type = "text/html"
}
