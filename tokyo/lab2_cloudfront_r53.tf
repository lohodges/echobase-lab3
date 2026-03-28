# # Explanation: DNS now points to CloudFront — nobody should ever see the ALB again.
# resource "aws_route53_record" "shinjuku_apex_to_cf01" {
#   zone_id = local.shinjuku_zone_id
#   name    = var.domain_name
#   type    = "A"

#   alias {
#     name                   = aws_cloudfront_distribution.shinjuku_cf01.domain_name
#     zone_id                = aws_cloudfront_distribution.shinjuku_cf01.hosted_zone_id
#     evaluate_target_health = false
#   }
# }

# # Explanation: app.shinjuku-growl.com also points to CloudFront — same doorway, different sign.
# resource "aws_route53_record" "shinjuku_app_to_cf01" {
#   zone_id = local.shinjuku_zone_id
#   name    = "${var.app_subdomain}.${var.domain_name}"
#   type    = "A"

#   alias {
#     name                   = aws_cloudfront_distribution.shinjuku_cf01.domain_name
#     zone_id                = aws_cloudfront_distribution.shinjuku_cf01.hosted_zone_id
#     evaluate_target_health = false
#   }
# }
