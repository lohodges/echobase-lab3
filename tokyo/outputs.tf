# Explanation: Outputs are your mission report—what got built and where to find it.
output "shinjuku_vpc_id" {
  value = aws_vpc.shinjuku_vpc01.id
}

output "shinjuku_public_subnet_ids" {
  value = aws_subnet.shinjuku_public_subnets[*].id
}

output "shinjuku_private_subnet_ids" {
  value = aws_subnet.shinjuku_private_subnets[*].id
}

# output "shinjuku_ec2_instance_id" {
#   value = aws_instance.shinjuku_ec201.id
# }

output "shinjuku_rds_endpoint" {
  value = aws_db_instance.shinjuku_rds01.address
}

output "shinjuku_sns_topic_arn" {
  value = aws_sns_topic.shinjuku_sns_topic01.arn
}

output "shinjuku_log_group_name" {
  value = aws_cloudwatch_log_group.shinjuku_log_group01.name
}

# added by Lonnie Hodges
#Bonus-A outputs (append to outputs.tf)
# Explanation: These outputs prove shinjuku built private hyperspace lanes (endpoints) instead of public chaos.
output "shinjuku_vpce_ssm_id" {
  value = aws_vpc_endpoint.shinjuku_vpce_ssm01.id
}

output "shinjuku_vpce_logs_id" {
  value = aws_vpc_endpoint.shinjuku_vpce_logs01.id
}

output "shinjuku_vpce_secrets_id" {
  value = aws_vpc_endpoint.shinjuku_vpce_secrets01.id
}

output "shinjuku_vpce_s3_id" {
  value = aws_vpc_endpoint.shinjuku_vpce_s3_gw01.id
}

output "shinjuku_private_ec2_instance_id_bonus" {
  value = aws_instance.shinjuku_ec201_private_bonus.id
}

# # added by Lonnie Hodges
# #Bonus-B outputs (append to outputs.tf)
# # Explanation: Outputs are the mission coordinates — where to point your browser and your blasters.
output "shinjuku_alb_dns_name" {
  value = aws_lb.shinjuku_alb01.dns_name
}

output "shinjuku_app_fqdn" {
  value = "https://${var.app_subdomain}.${var.domain_name}"
}

output "shinjuku_target_group_arn" {
  value = aws_lb_target_group.shinjuku_tg01.arn
}

output "shinjuku_acm_cert_arn" {
  value = aws_acm_certificate.shinjuku_acm_cert01.arn
}

# output "shinjuku_waf_arn" {
#   value = var.enable_waf ? aws_wafv2_web_acl.shinjuku_waf01[0].arn : null
# }

output "shinjuku_dashboard_name" {
  value = aws_cloudwatch_dashboard.shinjuku_dashboard01.dashboard_name
}

# Explanation: The apex URL is the front gate—humans type this when they forget subdomains.
output "shinjuku_apex_url_https" {
  value = "https://${var.domain_name}"
}

# Explanation: Log bucket name is where the footprints live—useful when hunting 5xx or WAF blocks.
output "shinjuku_alb_logs_bucket_name" {
  value = var.enable_alb_access_logs ? aws_s3_bucket.shinjuku_alb_logs_bucket01[0].bucket : null
}

# Explanation: Coordinates for the WAF log destination—shinjuku wants to know where the footprints landed.
output "shinjuku_waf_log_destination" {
  value = var.waf_log_destination
}

output "shinjuku_waf_cw_log_group_name" {
  value = var.waf_log_destination == "cloudwatch" ? aws_cloudwatch_log_group.shinjuku_waf_log_group01[0].name : null
}

output "shinjuku_waf_logs_s3_bucket" {
  value = var.waf_log_destination == "s3" ? aws_s3_bucket.shinjuku_waf_logs_bucket01[0].bucket : null
}

output "shinjuku_waf_firehose_name" {
  value = var.waf_log_destination == "firehose" ? aws_kinesis_firehose_delivery_stream.shinjuku_waf_firehose01[0].name : null
}

output "shinjuku_tgw01_id" {
  value = aws_ec2_transit_gateway.shinjuku_tgw01.id
}
output "shinjuku_tgw01_default_route_table_id" {
  value = aws_ec2_transit_gateway.shinjuku_tgw01.association_default_route_table_id
}