############################################
# Locals (naming convention: Liberdade-*)
############################################
locals {
  name_prefix = var.project_name

  # Explanation: This is the roar address — where the galaxy finds your app.
  liberdade_fqdn = var.domain_name

  # Explanation: liberdade needs a home planet—Route53 hosted zone is your DNS territory.
  liberdade_zone_name = var.domain_name

  # Explanation: Use either Terraform-managed zone or a pre-existing zone ID (students choose their destiny).
  liberdade_zone_id = var.manage_route53_in_terraform #? aws_route53_zone.liberdade_zone01[0].zone_id : var.route53_hosted_zone_id

  # Explanation: This is the app address that will growl at the galaxy (app.echobase.click).
  liberdade_app_fqdn = "${var.app_subdomain}.${var.domain_name}"
}

# added by Lonnie Hodges on 2026-01-17
############################################
# Bonus A - Data + Locals
############################################

# Explanation: Chewbacca wants to know “who am I in this galaxy?” so ARNs can be scoped properly.
data "aws_caller_identity" "liberdade_self01" {}

# Explanation: Region matters—hyperspace lanes change per sector.
data "aws_region" "liberdade_region01" {}
# ^^^ added by Lonnie Hodges on 2026-01-17

############################################
# VPC + Internet Gateway + Transit Gateway
############################################

# Explanation: Liberdade needs a hyperlane—this VPC is the Millennium Falcon’s flight corridor.
resource "aws_vpc" "liberdade_vpc01" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc01"
  }
}

# Explanation: Even Wookiees need to reach the wider galaxy—IGW is your door to the public internet.
resource "aws_internet_gateway" "liberdade_igw01" {
  vpc_id = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-igw01"
  }
}


# Explanation: Liberdade is São Paulo’s Japanese town—local doctors, local compute, remote data.
resource "aws_ec2_transit_gateway" "liberdade_tgw01" {
  description = "liberdade-tgw01 (Sao Paulo spoke)"
  tags        = { Name = "liberdade-tgw01" }
}

# Explanation: Liberdade attaches to its VPC—compute can now reach Tokyo legally, through the controlled corridor.
resource "aws_ec2_transit_gateway_vpc_attachment" "liberdade_attach_sp_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.liberdade_tgw01.id
  vpc_id             = aws_vpc.liberdade_vpc01.id
  subnet_ids         = [aws_subnet.liberdade_private_subnets[0].id, aws_subnet.liberdade_private_subnets[1].id]
  tags               = { Name = "liberdade-attach-sp-vpc01" }
}

############################################
# Subnets (Public + Private)
############################################

# Explanation: Public subnets are like docking bays—ships can land directly from space (internet).
resource "aws_subnet" "liberdade_public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.liberdade_vpc01.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet0${count.index + 1}"
  }
}

# Explanation: Private subnets are the hidden Rebel base—no direct access from the internet.
resource "aws_subnet" "liberdade_private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.liberdade_vpc01.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-private-subnet0${count.index + 1}"
  }
}

############################################
# NAT Gateway + EIP
############################################

# Explanation: Liberdade wants the private base to call home—EIP gives the NAT a stable “holonet address.”
resource "aws_eip" "liberdade_nat_eip01" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip01"
  }
}

# Explanation: NAT is Liberdade’s smuggler tunnel—private subnets can reach out without being seen.
resource "aws_nat_gateway" "liberdade_nat01" {
  allocation_id = aws_eip.liberdade_nat_eip01.id
  subnet_id     = aws_subnet.liberdade_public_subnets[0].id # NAT in a public subnet
  tags = {
    Name = "${local.name_prefix}-nat01"
  }

  depends_on = [aws_internet_gateway.liberdade_igw01]
}

############################################
# Routing (Public + Private Route Tables)
############################################
# Explanation: Liberdade knows the way to Shinjuku—Tokyo CIDR routes go through the TGW corridor.
resource "aws_route" "liberdade_to_tokyo_route01" {
  route_table_id         = aws_route_table.liberdade_private_rt01.id
  destination_cidr_block = "10.124.0.0/16" # Tokyo VPC CIDR (students supply)
  transit_gateway_id     = aws_ec2_transit_gateway.liberdade_tgw01.id
}

# Explanation: Public route table = “open lanes” to the galaxy via IGW.
resource "aws_route_table" "liberdade_public_rt01" {
  vpc_id = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-public-rt01"
  }
}

# Explanation: This route is the Kessel Run—0.0.0.0/0 goes out the IGW.
resource "aws_route" "liberdade_public_default_route" {
  route_table_id         = aws_route_table.liberdade_public_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.liberdade_igw01.id
}

# Explanation: Attach public subnets to the “public lanes.”
resource "aws_route_table_association" "liberdade_public_rta" {
  count          = length(aws_subnet.liberdade_public_subnets)
  subnet_id      = aws_subnet.liberdade_public_subnets[count.index].id
  route_table_id = aws_route_table.liberdade_public_rt01.id
}

# Explanation: Private route table = “stay hidden, but still ship supplies.”
resource "aws_route_table" "liberdade_private_rt01" {
  vpc_id = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-private-rt01"
  }
}

# Explanation: Private subnets route outbound internet via NAT (Liberdade-approved stealth).
resource "aws_route" "liberdade_private_default_route" {
  route_table_id         = aws_route_table.liberdade_private_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.liberdade_nat01.id
}

# Explanation: Attach private subnets to the “stealth lanes.”
resource "aws_route_table_association" "liberdade_private_rta" {
  count          = length(aws_subnet.liberdade_private_subnets)
  subnet_id      = aws_subnet.liberdade_private_subnets[count.index].id
  route_table_id = aws_route_table.liberdade_private_rt01.id
}

############################################
# Security Groups (EC2 + RDS)
############################################

# Explanation: EC2 SG is Liberdade’s bodyguard—only let in what you mean to.
resource "aws_security_group" "liberdade_ec2_sg01" {
  name        = "${local.name_prefix}-ec2-sg01"
  description = "EC2 app security group"
  vpc_id      = aws_vpc.liberdade_vpc01.id

  tags = {
    Name = "${local.name_prefix}-ec2-sg01"
  }
}

# TODO: student adds inbound rules (HTTP 80, SSH 22 from their IP)
# added by Lonnie Hodges
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.liberdade_ec2_sg01.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "out_ec2_all" {
  security_group_id = aws_security_group.liberdade_ec2_sg01.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Explanation: liberdade only opens the hangar door — allow ALB -> EC2 on app port (e.g., 80).
resource "aws_vpc_security_group_ingress_rule" "liberdade_ec2_ingress_from_alb01" {
  security_group_id            = aws_security_group.liberdade_ec2_sg01.id
  referenced_security_group_id = aws_security_group.liberdade_alb_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80

  # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
}

# Explanation: liberdade only opens the hangar door — allow ALB -> EC2 on app port (e.g., 443).
resource "aws_vpc_security_group_ingress_rule" "liberdade_tls_ec2_ingress_from_alb01" {
  security_group_id            = aws_security_group.liberdade_ec2_sg01.id
  referenced_security_group_id = aws_security_group.liberdade_alb_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
}

# added by Lonnie Hodges on 2026-01-19
############################################
# Security Group for VPC Interface Endpoints
############################################

# Explanation: Even endpoints need guards—Liberdade posts a Wookiee at every airlock.
resource "aws_security_group" "liberdade_vpce_sg01" {
  name        = "${local.name_prefix}-vpce-sg01"
  description = "SG for VPC Interface Endpoints"
  vpc_id      = aws_vpc.liberdade_vpc01.id

  # NOTE: Interface endpoints ENIs receive traffic on 443.

  tags = {
    Name = "${local.name_prefix}-vpce-sg01"
  }
}

# bonus_a.tf TODO: Students must allow inbound 443 FROM the EC2 SG (or VPC CIDR) to endpoints.
# https://docs.aws.amazon.com/vpc/latest/privatelink/create-interface-endpoint.html
resource "aws_vpc_security_group_ingress_rule" "https_from_ec2_sg01" {
  security_group_id            = aws_security_group.liberdade_vpce_sg01.id
  referenced_security_group_id = aws_security_group.liberdade_ec2_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
# ^^^ added by Lonnie Hodges on 2026-01-19

############################################
# IAM Role + Instance Profile for EC2
############################################
# added by Lonnie Hodges
resource "aws_iam_policy" "policy_ec2_read_secret" {
  name        = "liberdade_read_specific_secret"
  path        = "/"
  description = "EC2 must read secrets/params during recovery—give it access."

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "ReadSpecificSecret",
        "Effect" : "Allow",
        "Action" : ["secretsmanager:GetSecretValue"],
        # "Resource" : "arn:aws:secretsmanager:<REGION>:<ACCOUNT ID>:secret:shinjuku/rds/mysql*"
        "Resource" : "arn:aws:secretsmanager:sa-east-1:746669200167:secret:shinjuku/rds/mysql*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "liberdade_ec2_secrets_attach" {
  role       = aws_iam_role.liberdade_ec2_role01.name
  policy_arn = aws_iam_policy.policy_ec2_read_secret.arn
}
# added by Lonnie Hodges

# Explanation: Liberdade refuses to carry static keys—this role lets EC2 assume permissions safely.
resource "aws_iam_role" "liberdade_ec2_role01" {
  name = "${local.name_prefix}-ec2-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Explanation: These policies are your Wookiee toolbelt—tighten them (least privilege) as a stretch goal.
resource "aws_iam_role_policy_attachment" "liberdade_ec2_ssm_attach" {
  role       = aws_iam_role.liberdade_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# added by Lonnie Hodges on 2026-01-19
# COMMENTED OUT to use least privilege 
# # Explanation: EC2 must read secrets/params during recovery—give it access (students should scope it down).
# resource "aws_iam_role_policy_attachment" "liberdade_ec2_secrets_attach" {
#   role       = aws_iam_role.liberdade_ec2_role01.name
#   policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" # TODO: student replaces w/ least privilege
# }

# Explanation: CloudWatch logs are the “ship’s black box”—you need them when things explode.
resource "aws_iam_role_policy_attachment" "liberdade_ec2_cw_attach" {
  role       = aws_iam_role.liberdade_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Explanation: Instance profile is the harness that straps the role onto the EC2 like bandolier ammo.
resource "aws_iam_instance_profile" "liberdade_instance_profile01" {
  name = "${local.name_prefix}-instance-profile01"
  role = aws_iam_role.liberdade_ec2_role01.name
}

# added by Lonnie Hodges on 2026-01-19
############################################
# Least-Privilege IAM (BONUS A)
############################################

# Explanation: Liberdade doesn’t hand out the Falcon keys—this policy scopes reads to your lab paths only.
resource "aws_iam_policy" "liberdade_leastpriv_read_params01" {
  name        = "${local.name_prefix}-lp-ssm-read01"
  description = "Least-privilege read for SSM Parameter Store under /lab/db/*"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadLabDbParams"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.liberdade_region01.region}:${data.aws_caller_identity.liberdade_self01.account_id}:parameter/lab/db/*"
        ]
      }
    ]
  })
}

# Explanation: When the Falcon logs scream, this lets liberdade ship logs to CloudWatch without giving away the Death Star plans.
resource "aws_iam_policy" "liberdade_leastpriv_cwlogs01" {
  name        = "${local.name_prefix}-lp-cwlogs01"
  description = "Least-privilege CloudWatch Logs write for the app log group"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.liberdade_log_group01.arn}:*"
        ]
      }
    ]
  })
}

# Explanation: Attach the scoped policies—liberdade loves power, but only the safe kind.
resource "aws_iam_role_policy_attachment" "liberdade_attach_lp_params01" {
  role       = aws_iam_role.liberdade_ec2_role01.name
  policy_arn = aws_iam_policy.liberdade_leastpriv_read_params01.arn
}

resource "aws_iam_role_policy_attachment" "liberdade_attach_lp_cwlogs01" {
  role       = aws_iam_role.liberdade_ec2_role01.name
  policy_arn = aws_iam_policy.liberdade_leastpriv_cwlogs01.arn
}
# ^^^ added by Lonnie Hodges on 2026-01-19


############################################
# EC2 Instance (App Host)
############################################

# Explanation: This is your “Han Solo box”—it talks to RDS and complains loudly when the DB is down.
# resource "aws_instance" "liberdade_ec201" {
#   ami                    = var.ec2_ami_id
#   instance_type          = var.ec2_instance_type
#   subnet_id              = aws_subnet.liberdade_private_subnets[0].id
#   vpc_security_group_ids = [aws_security_group.liberdade_ec2_sg01.id]
#   iam_instance_profile   = aws_iam_instance_profile.liberdade_instance_profile01.name

#   # TODO: student supplies user_data to install app + CW agent + configure log shipping
#   # added by Lonnie Hodges
#   user_data = file("${path.module}/user_data.sh")

#   tags = {
#     Name = "${local.name_prefix}-ec201"
#   }
# }

# added by Lonnie Hodges on 2026-01-17
# from bonus_a.tf
############################################
# Move EC2 into PRIVATE subnet (no public IP)
############################################

# Explanation: Liberdade hates exposure—private subnets keep your compute off the public holonet.
resource "aws_instance" "liberdade_ec201_private_bonus" {
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.liberdade_private_subnets[0].id
  vpc_security_group_ids = [aws_security_group.liberdade_ec2_sg01.id]
  iam_instance_profile   = aws_iam_instance_profile.liberdade_instance_profile01.name

  # TODO: Students should remove/disable SSH inbound rules entirely and rely on SSM.
  # TODO: Students add user_data that installs app + CW agent; for true hard mode use a baked AMI.
  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name = "${local.name_prefix}-ec201-private"
  }
}

############################################
# CloudWatch Logs (Log Group)
############################################

# Explanation: When the Falcon is on fire, logs tell you *which* wire sparked—ship them centrally.
resource "aws_cloudwatch_log_group" "liberdade_log_group01" {
  name              = "/aws/ec2/${local.name_prefix}-rds-app"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-log-group01"
  }
}

# added by Lonnie Hodges 2026-01-15
resource "aws_cloudwatch_log_stream" "liberdade_log_stream01" {
  name           = "${local.name_prefix}-rds-app"
  log_group_name = aws_cloudwatch_log_group.liberdade_log_group01.name
}

############################################
# Custom Metric + Alarm (Skeleton)
############################################
# Explanation: Metrics are Liberdade’s growls—when they spike, something is wrong.
# NOTE: Students must emit the metric from app/agent; this just declares the alarm.
# Added by Lonnie Hodges:  https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/aws-services-cloudwatch-metrics.html
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/download-CloudWatch-Agent-on-EC2-Instance-commandline-first.html
resource "aws_cloudwatch_metric_alarm" "liberdade_db_alarm01" {
  alarm_name          = "${local.name_prefix}-db-connection-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Lab/RDSApp"
  period              = 300
  statistic           = "Sum"
  threshold           = 3

  alarm_actions = [aws_sns_topic.liberdade_sns_topic01.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-db-fail"
  }
}

############################################
# SNS (PagerDuty simulation)
############################################

# Explanation: SNS is the distress beacon—when the DB dies, the galaxy (your inbox) must hear about it.
resource "aws_sns_topic" "liberdade_sns_topic01" {
  name = "${local.name_prefix}-db-incidents"
}

# Explanation: Email subscription = “poor man’s PagerDuty”—still enough to wake you up at 3AM.
resource "aws_sns_topic_subscription" "liberdade_sns_sub01" {
  topic_arn = aws_sns_topic.liberdade_sns_topic01.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

############################################
# (Optional but realistic) VPC Endpoints (Skeleton)
############################################

# Explanation: Endpoints keep traffic inside AWS like hyperspace lanes—less exposure, more control.
# TODO: students can add endpoints for SSM, Logs, Secrets Manager if doing “no public egress” variant.
# resource "aws_vpc_endpoint" "liberdade_vpce_ssm" { ... }

# added by Lonnie Hodges on 2026-01-19
############################################
# VPC Endpoint - S3 (Gateway)
############################################

# Explanation: S3 is the supply depot—without this, your private world starves (updates, artifacts, logs).
resource "aws_vpc_endpoint" "liberdade_vpce_s3_gw01" {
  vpc_id            = aws_vpc.liberdade_vpc01.id
  service_name      = "com.amazonaws.${data.aws_region.liberdade_region01.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.liberdade_private_rt01.id
  ]

  tags = {
    Name = "${local.name_prefix}-vpce-s3-gw01"
  }
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-19
############################################
# VPC Endpoints - SSM (Interface)
############################################

# Explanation: SSM is your Force choke—remote control without SSH, and nobody sees your keys.
resource "aws_vpc_endpoint" "liberdade_vpce_ssm01" {
  vpc_id              = aws_vpc.liberdade_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.liberdade_region01.region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.liberdade_private_subnets[*].id
  security_group_ids = [aws_security_group.liberdade_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-ssm01"
  }
}

# Explanation: ec2messages is the Wookiee messenger—SSM sessions won’t work without it.
resource "aws_vpc_endpoint" "liberdade_vpce_ec2messages01" {
  vpc_id              = aws_vpc.liberdade_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.liberdade_region01.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.liberdade_private_subnets[*].id
  security_group_ids = [aws_security_group.liberdade_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-ec2messages01"
  }
}

# Explanation: ssmmessages is the holonet channel—Session Manager needs it to talk back.
resource "aws_vpc_endpoint" "liberdade_vpce_ssmmessages01" {
  vpc_id              = aws_vpc.liberdade_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.liberdade_region01.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.liberdade_private_subnets[*].id
  security_group_ids = [aws_security_group.liberdade_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-ssmmessages01"
  }
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-19
############################################
# VPC Endpoint - CloudWatch Logs (Interface)
############################################

# Explanation: CloudWatch Logs is the ship's black box—liberdade wants crash data, always.
resource "aws_vpc_endpoint" "liberdade_vpce_logs01" {
  vpc_id              = aws_vpc.liberdade_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.liberdade_region01.region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.liberdade_private_subnets[*].id
  security_group_ids = [aws_security_group.liberdade_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-logs01"
  }
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-19
############################################
# VPC Endpoint - Secrets Manager (Interface)
############################################

# Explanation: Secrets Manager is the locked vault—liberdade doesn't put passwords on sticky notes.
resource "aws_vpc_endpoint" "liberdade_vpce_secrets01" {
  vpc_id              = aws_vpc.liberdade_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.liberdade_region01.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.liberdade_private_subnets[*].id
  security_group_ids = [aws_security_group.liberdade_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-secrets01"
  }
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-19
############################################
# Optional: VPC Endpoint - KMS (Interface)
############################################

# Explanation: KMS is the encryption kyber crystal—liberdade prefers locked doors AND locked safes.
resource "aws_vpc_endpoint" "liberdade_vpce_kms01" {
  vpc_id              = aws_vpc.liberdade_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.liberdade_region01.region}.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.liberdade_private_subnets[*].id
  security_group_ids = [aws_security_group.liberdade_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-kms01"
  }
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-19
############################################
# Security Group: ALB
############################################

# Explanation: The ALB SG is the blast shield — only allow what the Rebellion needs (80/443).
resource "aws_security_group" "liberdade_alb_sg01" {
  name        = "${var.project_name}-alb-sg01"
  description = "ALB security group"
  vpc_id      = aws_vpc.liberdade_vpc01.id

  # TODO: students add inbound 80/443 from 0.0.0.0/0
  # TODO: students set outbound to target group port (usually 80) to private targets

  tags = {
    Name = "${var.project_name}-alb-sg01"
  }
}

# No longer needed. INternet users should not be able access the ALB
# # Explanation: liberdade only opens the hangar door — allow ALB -> EC2 on app port (e.g., 80).
# resource "aws_vpc_security_group_ingress_rule" "liberdade_ec2_ingress_from_internet" {
#   security_group_id = aws_security_group.liberdade_alb_sg01.id
#   cidr_ipv4         = "0.0.0.0/0"
#   ip_protocol       = "tcp"
#   from_port         = 80
#   to_port           = 80

#   # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
# }

# # chobase only opens the hangar door — allow ALB -> EC2 on app port (e.g., 443).
# resource "aws_vpc_security_group_ingress_rule" "liberdade_tls_ec2_ingress_from_internet" {
#   #security_group_id = aws_security_group.liberdade_alb_sg01.id
#   security_group_id = aws_security_group.liberdade_alb_sg01.id
#   cidr_ipv4         = "0.0.0.0/0"
#   ip_protocol       = "tcp"
#   from_port         = 443
#   to_port           = 443

#   # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
# }

# Explanation: liberdade only opens the hangar door — allow ALB -> EC2 on app port (e.g., 443).
resource "aws_vpc_security_group_egress_rule" "liberdade_egress_to_ec2" {
  security_group_id            = aws_security_group.liberdade_alb_sg01.id
  referenced_security_group_id = aws_security_group.liberdade_ec2_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80

  # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
}

# Explanation: liberdade only opens the hangar door — allow ALB -> EC2 on app port (e.g., 443).
resource "aws_vpc_security_group_egress_rule" "liberdade_tls_egress_to_ec2" {
  security_group_id            = aws_security_group.liberdade_alb_sg01.id
  referenced_security_group_id = aws_security_group.liberdade_ec2_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
}


############################################
# Application Load Balancer
############################################

# Explanation: The ALB is your public customs checkpoint — it speaks TLS and forwards to private targets.
resource "aws_lb" "liberdade_alb01" {
  name               = "${var.project_name}-alb01"
  load_balancer_type = "application"
  internal           = false

  security_groups = [aws_security_group.liberdade_alb_sg01.id]
  subnets         = aws_subnet.liberdade_public_subnets[*].id

  # TODO: students can enable access logs to S3 as a stretch goal
  # Explanation: Turn on access logs—Liberdade wants receipts when something goes wrong.
  # added by Lonnie Hodges on 2026-01-20
  access_logs {
    bucket  = aws_s3_bucket.liberdade_alb_logs_bucket01[0].bucket
    prefix  = var.alb_access_logs_prefix
    enabled = var.enable_alb_access_logs
  }

  tags = {
    Name = "${var.project_name}-alb01"
  }
}

############################################
# Target Group + Attachment
############################################

# Explanation: Target groups are liberdade's "who do I forward to?" list — private EC2 lives here.
resource "aws_lb_target_group" "liberdade_tg01" {
  name     = "${var.project_name}-tg01"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.liberdade_vpc01.id

  # TODO: students set health check path to something real (e.g., /health)
  health_check {
    enabled             = true
    interval            = 30
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    matcher             = "200-399"
  }

  tags = {
    Name = "${var.project_name}-tg01"
  }
}

# Explanation: liberdade personally introduces the ALB to the private EC2 — "this is my friend, don't shoot."
resource "aws_lb_target_group_attachment" "liberdade_tg_attach01" {
  target_group_arn = aws_lb_target_group.liberdade_tg01.arn
  target_id        = aws_instance.liberdade_ec201_private_bonus.id
  port             = 80

  # TODO: students ensure EC2 security group allows inbound from ALB SG on this port (rule above)
}

# resource "aws_lb_target_group_attachment" "liberdade_tg_attach02" {
#   target_group_arn = aws_lb_target_group.liberdade_tg01.arn
#   target_id        = aws_instance.liberdade_ec201.id
#   port             = 80

#   # TODO: students ensure EC2 security group allows inbound from ALB SG on this port (rule above)
# }

############################################
# ALB Listeners: HTTP -> HTTPS redirect, HTTPS -> TG
############################################

# Explanation: HTTP listener is the decoy airlock — it redirects everyone to the secure entrance.
resource "aws_lb_listener" "liberdade_http_listener01" {
  load_balancer_arn = aws_lb.liberdade_alb01.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# added by Lonnie Hodges on 2026-01-20
############################################
# WAFv2 Web ACL (Basic managed rules)
############################################

# # Explanation: WAF is the shield generator — it blocks the cheap blaster fire before it hits your ALB.
# resource "aws_wafv2_web_acl" "liberdade_waf01" {
#   count = var.enable_waf ? 1 : 0

#   name  = "${var.project_name}-waf01"
#   scope = "REGIONAL"

#   default_action {
#     allow {}
#   }

#   visibility_config {
#     cloudwatch_metrics_enabled = true
#     metric_name                = "${var.project_name}-waf01"
#     sampled_requests_enabled   = true
#   }

#   # Explanation: AWS managed rules are like hiring Rebel commandos — they’ve seen every trick.
#   rule {
#     name     = "AWSManagedRulesCommonRuleSet"
#     priority = 1

#     override_action {
#       none {}
#     }

#     statement {
#       managed_rule_group_statement {
#         name        = "AWSManagedRulesCommonRuleSet"
#         vendor_name = "AWS"
#       }
#     }

#     visibility_config {
#       cloudwatch_metrics_enabled = true
#       metric_name                = "${var.project_name}-waf-common"
#       sampled_requests_enabled   = true
#     }
#   }

#   tags = {
#     Name = "${var.project_name}-waf01"
#   }
# }

# # Explanation: Attach the shield generator to the customs checkpoint — ALB is now protected.
# resource "aws_wafv2_web_acl_association" "liberdade_waf_assoc01" {
#   count = var.enable_waf ? 1 : 0

#   resource_arn = aws_lb.liberdade_alb01.arn
#   web_acl_arn  = aws_wafv2_web_acl.liberdade_waf01[0].arn
# }
# # ^^^ added by Lonnie Hodges on 2026-01-20

# added by Lonnie Hodges on 2026-01-20
############################################
# CloudWatch Alarm: ALB 5xx -> SNS
############################################

# Explanation: When the ALB starts throwing 5xx, that’s the Falcon coughing — page the on-call Wookiee.
resource "aws_cloudwatch_metric_alarm" "liberdade_alb_5xx_alarm01" {
  alarm_name          = "${var.project_name}-alb-5xx-alarm01"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alb_5xx_evaluation_periods
  threshold           = var.alb_5xx_threshold
  period              = var.alb_5xx_period_seconds
  statistic           = "Sum"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"

  dimensions = {
    LoadBalancer = aws_lb.liberdade_alb01.arn_suffix
  }

  alarm_actions = [aws_sns_topic.liberdade_sns_topic02.arn]

  tags = {
    Name = "${var.project_name}-alb-5xx-alarm01"
  }
}

# added by Lonnie Hodges on 2026-01-23
# Explanation: SNS is the distress beacon—when the DB dies, the galaxy (your inbox) must hear about it.
resource "aws_sns_topic" "liberdade_sns_topic02" {
  name = "${local.name_prefix}-alb-5xx-incidents"
}

# Explanation: Email subscription = “poor man’s PagerDuty”—still enough to wake you up at 3AM.
resource "aws_sns_topic_subscription" "liberdade_sns_sub02" {
  topic_arn = aws_sns_topic.liberdade_sns_topic02.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

############################################
# CloudWatch Dashboard (Skeleton)
############################################

# Explanation: Dashboards are your cockpit HUD — liberdade wants dials, not vibes.
resource "aws_cloudwatch_dashboard" "liberdade_dashboard01" {
  dashboard_name = "${var.project_name}-dashboard01"

  # TODO: students can expand widgets; this is a minimal workable skeleton
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.liberdade_alb01.arn_suffix],
            [".", "HTTPCode_ELB_5XX_Count", ".", aws_lb.liberdade_alb01.arn_suffix]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Liberdade ALB: Requests + 5XX"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.liberdade_alb01.arn_suffix]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Liberdade ALB: Target Response Time"
        }
      }
    ]
  })
}

############################################
# S3 bucket for ALB access logs
############################################

# Explanation: This bucket is liberdade's log vault—every visitor to the ALB leaves footprints here.
resource "aws_s3_bucket" "liberdade_alb_logs_bucket01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = "${var.project_name}-alb-logs-${data.aws_caller_identity.liberdade_self01.account_id}"

  force_destroy = true

  tags = {
    Name = "${var.project_name}-alb-logs-bucket01"
  }
}

# Explanation: Block public access—liberdade does not publish the ship's black box to the galaxy.
resource "aws_s3_bucket_public_access_block" "liberdade_alb_logs_pab01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.liberdade_alb_logs_bucket01[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Bucket ownership controls prevent log delivery chaos—liberdade likes clean chain-of-custody.
resource "aws_s3_bucket_ownership_controls" "liberdade_alb_logs_owner01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.liberdade_alb_logs_bucket01[0].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Explanation: TLS-only—liberdade growls at plaintext and throws it out an airlock.
resource "aws_s3_bucket_policy" "liberdade_alb_logs_policy01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.liberdade_alb_logs_bucket01[0].id

  # NOTE: This is a skeleton. Students may need to adjust for region/account specifics.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.liberdade_alb_logs_bucket01[0].arn,
          "${aws_s3_bucket.liberdade_alb_logs_bucket01[0].arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        Sid    = "AllowELBPutObject"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.liberdade_alb_logs_bucket01[0].arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.liberdade_self01.account_id}/*"
      },

    ]
  })
}
# ^^^ added by Lonnie Hodges on 2026-01-20

# added by Lonnie Hodges on 2026-01-21
############################################
# Bonus B - WAF Logging (CloudWatch Logs OR S3 OR Firehose)
# One destination per Web ACL, choose via var.waf_log_destination.
############################################

############################################
# Option 1: CloudWatch Logs destination
############################################

# Explanation: WAF logs in CloudWatch are your “blaster-cam footage”—fast search, fast triage, fast truth.
resource "aws_cloudwatch_log_group" "liberdade_waf_log_group01" {
  count = var.waf_log_destination == "cloudwatch" ? 1 : 0

  # NOTE: AWS requires WAF log destination names start with aws-waf-logs- (students must not rename this).
  name              = "aws-waf-logs-${var.project_name}-webacl01"
  retention_in_days = var.waf_log_retention_days

  tags = {
    Name = "${var.project_name}-waf-log-group01"
  }
}

# # Explanation: This wire connects the shield generator to the black box—WAF -> CloudWatch Logs.
# resource "aws_wafv2_web_acl_logging_configuration" "liberdade_waf_logging01" {
#   count = var.enable_waf && var.waf_log_destination == "cloudwatch" ? 1 : 0

#   resource_arn = aws_wafv2_web_acl.liberdade_waf01[0].arn
#   log_destination_configs = [
#     aws_cloudwatch_log_group.liberdade_waf_log_group01[0].arn
#   ]

#   # TODO: Students can add redacted_fields (authorization headers, cookies, etc.) as a stretch goal.
#   # redacted_fields { ... }

#   depends_on = [aws_wafv2_web_acl.liberdade_waf01]
# }

############################################
# Option 2: S3 destination (direct)
############################################

# Explanation: S3 WAF logs are the long-term archive—liberdade likes receipts that survive dashboards.
resource "aws_s3_bucket" "liberdade_waf_logs_bucket01" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  bucket = "aws-waf-logs-${var.project_name}-${data.aws_caller_identity.liberdade_self01.account_id}"

  # added by Lonnie Hodges on 2026-01-21
  force_destroy = true

  tags = {
    Name = "${var.project_name}-waf-logs-bucket01"
  }
}

# Explanation: Public access blocked—WAF logs are not a bedtime story for the entire internet.
resource "aws_s3_bucket_public_access_block" "liberdade_waf_logs_pab01" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  bucket                  = aws_s3_bucket.liberdade_waf_logs_bucket01[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# # Explanation: Connect shield generator to archive vault—WAF -> S3.
# resource "aws_wafv2_web_acl_logging_configuration" "liberdade_waf_logging_s3_01" {
#   count = var.enable_waf && var.waf_log_destination == "s3" ? 1 : 0

#   resource_arn = aws_wafv2_web_acl.liberdade_waf01[0].arn
#   log_destination_configs = [
#     aws_s3_bucket.liberdade_waf_logs_bucket01[0].arn
#   ]

#   depends_on = [aws_wafv2_web_acl.liberdade_waf01]
# }

############################################
# Option 3: Firehose destination (classic “stream then store”)
############################################

# Explanation: Firehose is the conveyor belt—WAF logs ride it to storage (and can fork to SIEM later).
resource "aws_s3_bucket" "liberdade_firehose_waf_dest_bucket01" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  bucket = "${var.project_name}-waf-firehose-dest-${data.aws_caller_identity.liberdade_self01.account_id}"

  # added by Lonnie Hodges on 2026-01-21
  force_destroy = true

  tags = {
    Name = "${var.project_name}-waf-firehose-dest-bucket01"
  }
}

# Explanation: Firehose needs a role—liberdade doesn't let random droids write into storage.
resource "aws_iam_role" "liberdade_firehose_role01" {
  count = var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${var.project_name}-firehose-role01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Explanation: Minimal permissions—allow Firehose to put objects into the destination bucket.
resource "aws_iam_role_policy" "liberdade_firehose_policy01" {
  count = var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${var.project_name}-firehose-policy01"
  role  = aws_iam_role.liberdade_firehose_role01[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.liberdade_firehose_waf_dest_bucket01[0].arn,
          "${aws_s3_bucket.liberdade_firehose_waf_dest_bucket01[0].arn}/*"
        ]
      }
    ]
  })
}

# Explanation: The delivery stream is the belt itself—logs move from WAF -> Firehose -> S3.
resource "aws_kinesis_firehose_delivery_stream" "liberdade_waf_firehose01" {
  count       = var.waf_log_destination == "firehose" ? 1 : 0
  name        = "aws-waf-logs-${var.project_name}-firehose01"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.liberdade_firehose_role01[0].arn
    bucket_arn = aws_s3_bucket.liberdade_firehose_waf_dest_bucket01[0].arn
    prefix     = "waf-logs/"
  }
}

# Explanation: Connect shield generator to conveyor belt—WAF -> Firehose stream.
# resource "aws_wafv2_web_acl_logging_configuration" "liberdade_waf_logging_firehose01" {
#   count = var.enable_waf && var.waf_log_destination == "firehose" ? 1 : 0

#   resource_arn = aws_wafv2_web_acl.liberdade_waf01[0].arn
#   log_destination_configs = [
#     aws_kinesis_firehose_delivery_stream.liberdade_waf_firehose01[0].arn
#   ]

#   depends_on = [aws_wafv2_web_acl.liberdade_waf01]
# }
# ^^^ added by Lonnie Hodges on 2026-01-21