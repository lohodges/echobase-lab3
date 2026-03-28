# added by Lonnie Hodges on 2026-02-01
############################################
# Lab 2B-Honors - Origin Driven Caching (Managed Policies)
############################################

# Explanation: shinjuku uses AWS-managed policies—battle-tested configs so students learn the real names.
data "aws_cloudfront_cache_policy" "shinjuku_use_origin_cache_headers01" {
  name = "UseOriginCacheControlHeaders"
}

# Explanation: Same idea, but includes query strings in the cache key when your API truly varies by them.
data "aws_cloudfront_cache_policy" "shinjuku_use_origin_cache_headers_qs01" {
  name = "UseOriginCacheControlHeaders-QueryStrings"
}

# Explanation: Origin request policies let us forward needed stuff without polluting the cache key.
# (Origin request policies are separate from cache policies.) :contentReference[oaicite:6]{index=6}
data "aws_cloudfront_origin_request_policy" "shinjuku_orp_all_viewer01" {
  name = "Managed-AllViewer"
}

data "aws_cloudfront_origin_request_policy" "shinjuku_orp_all_viewer_except_host01" {
  name = "Managed-AllViewerExceptHostHeader"
}
# ^^^ added by Lonnie Hodges on 2026-02-01

# Explanation: CloudFront is the only public doorway — shinjuku stands behind it with private infrastructure.
resource "aws_cloudfront_distribution" "shinjuku_cf01" {
  depends_on      = [aws_acm_certificate_validation.shinjuku_cf_acm_validation01]
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name}-cf01"

  origin {
    origin_id   = "${var.project_name}-alb-origin01"
    domain_name = aws_lb.shinjuku_alb01.dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # Explanation: CloudFront whispers the secret growl — the ALB only trusts this.
    custom_header {
      name  = "X-shinjuku-Growl"
      value = random_password.shinjuku_origin_header_value01.result
    }
  }

  ##############################################################
  #6) Patch your CloudFront distribution behaviors
  ##############################################################

  # Explanation: Default behavior is conservative—shinjuku assumes dynamic until proven static.
  default_cache_behavior {
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = aws_cloudfront_cache_policy.shinjuku_cache_api_disabled01.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.shinjuku_orp_api01.id
  }

  # Explanation: Static behavior is the speed lane—shinjuku caches it hard for performance.
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id            = aws_cloudfront_cache_policy.shinjuku_cache_static01.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.shinjuku_orp_static01.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.shinjuku_rsp_static01.id
  }

  # added by Lonnie Hodges on 2026-02-01
  ############################################
  # Lab 2B-Honors - A) /api/public-feed = origin-driven caching
  ############################################

  # Explanation: Public feed is cacheable—but only if the origin explicitly says so. shinjuku demands consent.
  ordered_cache_behavior {
    path_pattern           = "/api/public-feed"
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]

    # Honor Cache-Control from origin (and default to not caching without it). :contentReference[oaicite:8]{index=8}
    cache_policy_id = data.aws_cloudfront_cache_policy.shinjuku_use_origin_cache_headers01.id

    # Forward what origin needs. Keep it tight: don't forward everything unless required. :contentReference[oaicite:9]{index=9}
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.shinjuku_orp_all_viewer_except_host01.id
  }

  ############################################
  # Lab 2B-Honors - B) /api/* = still safe default (no caching)
  ############################################

  # Explanation: Everything else under /api is dangerous by default—shinjuku disables caching until proven safe.
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "${var.project_name}-alb-origin01"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = aws_cloudfront_cache_policy.shinjuku_cache_api_disabled01.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.shinjuku_orp_api01.id
  }
  # ^^^ added by Lonnie Hodges on 2026-02-01

  # Explanation: Attach WAF at the edge — now WAF moved to CloudFront.
  web_acl_id = aws_wafv2_web_acl.shinjuku_cf_waf01.arn

  # TODO: students set aliases for shinjuku-growl.com and app.shinjuku-growl.com
  aliases = [
    var.domain_name,
    "${var.app_subdomain}.${var.domain_name}"
  ]

  # TODO: students must use ACM cert in us-east-1 for CloudFront
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.shinjuku_cf_acm_validation01.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# added by Lonnie Hodges on 2026-02-02
# add CloudFront logging to S3
resource "aws_cloudwatch_log_delivery_source" "shinjuku_cf_delivery_source01" {
  region       = "us-east-1"
  name         = "${var.project_name}-logs-delivery-source-cf01"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.shinjuku_cf01.arn
}

resource "aws_s3_bucket" "shinjuku_cf_logs_bucket01" {
  bucket        = "shinjuku-cf-logs-${var.project_name}-${data.aws_caller_identity.shinjuku_self01.account_id}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-cf-logs-bucket01"
  }
}

# Explanation: Block public access—shinjuku does not publish CloudFront logs to the galaxy.
resource "aws_s3_bucket_public_access_block" "shinjuku_cf_logs_pab01" {
  bucket                  = aws_s3_bucket.shinjuku_cf_logs_bucket01.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Bucket ownership controls prevent log delivery chaos—shinjuku likes clean chain-of-custody.
resource "aws_s3_bucket_ownership_controls" "shinjuku_cf_logs_owner01" {
  bucket = aws_s3_bucket.shinjuku_cf_logs_bucket01.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Explanation: Allow the CloudWatch vended-logs delivery service to write CloudFront access logs.
resource "aws_s3_bucket_policy" "shinjuku_cf_logs_policy01" {
  bucket = aws_s3_bucket.shinjuku_cf_logs_bucket01.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSLogDeliveryWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.shinjuku_cf_logs_bucket01.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = data.aws_caller_identity.shinjuku_self01.account_id
          }
        }
      },
      {
        Sid       = "AWSLogDeliveryAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.shinjuku_cf_logs_bucket01.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.shinjuku_self01.account_id
          }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_delivery_destination" "shinjuku_cf_log_destination01" {
  region = "us-east-1"

  name          = "${var.project_name}-logs-to-s3"
  output_format = "plain"
  #output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = "${aws_s3_bucket.shinjuku_cf_logs_bucket01.arn}/CloudFront"
  }

  tags = {
    Name = "${var.project_name}-cf-logs-bucket01-delivery-dest"
  }
}

resource "aws_cloudwatch_log_delivery" "shinjuku_cf_log_delivery01" {
  region = "us-east-1"

  delivery_source_name     = aws_cloudwatch_log_delivery_source.shinjuku_cf_delivery_source01.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.shinjuku_cf_log_destination01.arn

  s3_delivery_configuration {
    suffix_path = "/${data.aws_caller_identity.shinjuku_self01.account_id}/{DistributionId}/{yyyy}/{MM}/{dd}/{HH}"
  }

  tags = {
    Name = "${var.project_name}-cf-logs-bucket01-delivery"
  }
}

# You’ll need this variable:
# variable "cloudfront_acm_cert_arn" {
#   description = "ACM certificate ARN in us-east-1 for CloudFront (covers shinjuku-growl.com and app.shinjuku-growl.com)."
#   type        = string
#   default     = "arn:aws:acm:us-east-1:746669200167:certificate/348e20c8-8fdb-4c5d-a4ea-7dcf37b00db2"
# }
