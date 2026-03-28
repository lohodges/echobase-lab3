############################################
# Locals (naming convention: Shinjuku-*)
############################################
locals {
  name_prefix = var.project_name

  # TODO: Students should lock this down after apply using the real secret ARN from outputs/state
  shinjuku_secret_arn_guess = "arn:aws:secretsmanager:${data.aws_region.shinjuku_region01.region}:${data.aws_caller_identity.shinjuku_self01.account_id}:secret:${local.name_prefix}/rds/mysql*"

  # Explanation: This is the roar address — where the galaxy finds your app.
  shinjuku_fqdn = var.domain_name

  # Explanation: shinjuku needs a home planet—Route53 hosted zone is your DNS territory.
  shinjuku_zone_name = var.domain_name

  # Explanation: Use either Terraform-managed zone or a pre-existing zone ID (students choose their destiny).
  shinjuku_zone_id = var.manage_route53_in_terraform #? aws_route53_zone.shinjuku_zone01[0].zone_id : var.route53_hosted_zone_id

  # Explanation: This is the app address that will growl at the galaxy (app.echobase.click).
  shinjuku_app_fqdn = "${var.app_subdomain}.${var.domain_name}"
}

# added by Lonnie Hodges on 2026-01-17
############################################
# Bonus A - Data + Locals
############################################

# Explanation: Chewbacca wants to know “who am I in this galaxy?” so ARNs can be scoped properly.
data "aws_caller_identity" "shinjuku_self01" {}

# Explanation: Region matters—hyperspace lanes change per sector.
data "aws_region" "shinjuku_region01" {}
# ^^^ added by Lonnie Hodges on 2026-01-17

############################################
# VPC + Internet Gateway + Transit Gateway
############################################

# Explanation: Shinjuku needs a hyperlane—this VPC is the Millennium Falcon’s flight corridor.
resource "aws_vpc" "shinjuku_vpc01" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc01"
  }
}

# Explanation: Even Wookiees need to reach the wider galaxy—IGW is your door to the public internet.
resource "aws_internet_gateway" "shinjuku_igw01" {
  vpc_id = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-igw01"
  }
}

# Explanation: Shinjuku Station is the hub—Tokyo is the data authority.
resource "aws_ec2_transit_gateway" "shinjuku_tgw01" {
  description = "shinjuku-tgw01 (Tokyo hub)"
  tags        = { Name = "shinjuku-tgw01" }
}

# Explanation: Shinjuku connects to the Tokyo VPC—this is the gate to the medical records vault.
resource "aws_ec2_transit_gateway_vpc_attachment" "shinjuku_attach_tokyo_vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.shinjuku_tgw01.id
  vpc_id             = aws_vpc.shinjuku_vpc01.id
  subnet_ids         = [aws_subnet.shinjuku_private_subnets[0].id, aws_subnet.shinjuku_private_subnets[1].id]
  tags               = { Name = "shinjuku-attach-tokyo-vpc01" }
}

############################################
# Subnets (Public + Private)
############################################

# Explanation: Public subnets are like docking bays—ships can land directly from space (internet).
resource "aws_subnet" "shinjuku_public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.shinjuku_vpc01.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet0${count.index + 1}"
  }
}

# Explanation: Private subnets are the hidden Rebel base—no direct access from the internet.
resource "aws_subnet" "shinjuku_private_subnets" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.shinjuku_vpc01.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-private-subnet0${count.index + 1}"
  }
}

############################################
# NAT Gateway + EIP
############################################

# Explanation: Shinjuku wants the private base to call home—EIP gives the NAT a stable “holonet address.”
resource "aws_eip" "shinjuku_nat_eip01" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip01"
  }
}

# Explanation: NAT is Shinjuku’s smuggler tunnel—private subnets can reach out without being seen.
resource "aws_nat_gateway" "shinjuku_nat01" {
  allocation_id = aws_eip.shinjuku_nat_eip01.id
  subnet_id     = aws_subnet.shinjuku_public_subnets[0].id # NAT in a public subnet

  tags = {
    Name = "${local.name_prefix}-nat01"
  }

  depends_on = [aws_internet_gateway.shinjuku_igw01]
}

############################################
# Routing (Public + Private Route Tables)
############################################
# Explanation: Shinjuku returns traffic to Liberdade—because doctors need answers, not one-way tunnels.
resource "aws_route" "shinjuku_to_sp_route01" {
  route_table_id         = aws_route_table.shinjuku_private_rt01.id
  destination_cidr_block = "10.136.0.0/16" # Sao Paulo VPC CIDR (students supply)
  transit_gateway_id     = aws_ec2_transit_gateway.shinjuku_tgw01.id
}

# Explanation: Public route table = “open lanes” to the galaxy via IGW.
resource "aws_route_table" "shinjuku_public_rt01" {
  vpc_id = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-public-rt01"
  }
}

# Explanation: This route is the Kessel Run—0.0.0.0/0 goes out the IGW.
resource "aws_route" "shinjuku_public_default_route" {
  route_table_id         = aws_route_table.shinjuku_public_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.shinjuku_igw01.id
}

# Explanation: Attach public subnets to the “public lanes.”
resource "aws_route_table_association" "shinjuku_public_rta" {
  count          = length(aws_subnet.shinjuku_public_subnets)
  subnet_id      = aws_subnet.shinjuku_public_subnets[count.index].id
  route_table_id = aws_route_table.shinjuku_public_rt01.id
}

# Explanation: Private route table = “stay hidden, but still ship supplies.”
resource "aws_route_table" "shinjuku_private_rt01" {
  vpc_id = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-private-rt01"
  }
}

# Explanation: Private subnets route outbound internet via NAT (Shinjuku-approved stealth).
resource "aws_route" "shinjuku_private_default_route" {
  route_table_id         = aws_route_table.shinjuku_private_rt01.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.shinjuku_nat01.id
}

# Explanation: Attach private subnets to the “stealth lanes.”
resource "aws_route_table_association" "shinjuku_private_rta" {
  count          = length(aws_subnet.shinjuku_private_subnets)
  subnet_id      = aws_subnet.shinjuku_private_subnets[count.index].id
  route_table_id = aws_route_table.shinjuku_private_rt01.id
}

############################################
# Security Groups (EC2 + RDS)
############################################

# Explanation: Tokyo’s vault opens only to approved clinics—Liberdade gets DB access, the public gets nothing.
resource "aws_security_group_rule" "shinjuku_rds_ingress_from_liberdade01" {
  type              = "ingress"
  security_group_id = aws_security_group.shinjuku_rds_sg01.id
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"

  cidr_blocks = ["10.136.0.0/16"] # Sao Paulo VPC CIDR (students supply)
}

# Explanation: EC2 SG is Shinjuku’s bodyguard—only let in what you mean to.
resource "aws_security_group" "shinjuku_ec2_sg01" {
  name        = "${local.name_prefix}-ec2-sg01"
  description = "EC2 app security group"
  vpc_id      = aws_vpc.shinjuku_vpc01.id


  tags = {
    Name = "${local.name_prefix}-ec2-sg01"
  }
}

# TODO: student adds inbound rules (HTTP 80, SSH 22 from their IP)
# added by Lonnie Hodges
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.shinjuku_ec2_sg01.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# TODO: student ensures outbound allows DB port to RDS SG (or allow all outbound)
# added by Lonnie Hodges
resource "aws_vpc_security_group_egress_rule" "out_to_rds" {
  security_group_id            = aws_security_group.shinjuku_ec2_sg01.id
  referenced_security_group_id = aws_security_group.shinjuku_rds_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "aws_vpc_security_group_egress_rule" "out_ec2_all" {
  security_group_id = aws_security_group.shinjuku_ec2_sg01.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Explanation: RDS SG is the Rebel vault—only the app server gets a keycard.
resource "aws_security_group" "shinjuku_rds_sg01" {
  name        = "${local.name_prefix}-rds-sg01"
  description = "RDS security group"
  vpc_id      = aws_vpc.shinjuku_vpc01.id

  tags = {
    Name = "${local.name_prefix}-rds-sg01"
  }
}

# TODO: student adds inbound MySQL 3306 from aws_security_group.shinjuku_ec2_sg01.id
# added by Lonnie Hodges
resource "aws_vpc_security_group_ingress_rule" "from_ec2" {
  security_group_id            = aws_security_group.shinjuku_rds_sg01.id
  referenced_security_group_id = aws_security_group.shinjuku_ec2_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

# Explanation: shinjuku only opens the hangar door — allow ALB -> EC2 on app port (e.g., 80).
resource "aws_vpc_security_group_ingress_rule" "shinjuku_ec2_ingress_from_alb01" {
  security_group_id            = aws_security_group.shinjuku_ec2_sg01.id
  referenced_security_group_id = aws_security_group.shinjuku_alb_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80

  # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
}

# Explanation: shinjuku only opens the hangar door — allow ALB -> EC2 on app port (e.g., 443).
resource "aws_vpc_security_group_ingress_rule" "shinjuku_tls_ec2_ingress_from_alb01" {
  security_group_id            = aws_security_group.shinjuku_ec2_sg01.id
  referenced_security_group_id = aws_security_group.shinjuku_alb_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
}

# added by Lonnie Hodges on 2026-01-19
############################################
# Security Group for VPC Interface Endpoints
############################################

# Explanation: Even endpoints need guards—Shinjuku posts a Wookiee at every airlock.
resource "aws_security_group" "shinjuku_vpce_sg01" {
  name        = "${local.name_prefix}-vpce-sg01"
  description = "SG for VPC Interface Endpoints"
  vpc_id      = aws_vpc.shinjuku_vpc01.id

  # NOTE: Interface endpoints ENIs receive traffic on 443.

  tags = {
    Name = "${local.name_prefix}-vpce-sg01"
  }
}

# bonus_a.tf TODO: Students must allow inbound 443 FROM the EC2 SG (or VPC CIDR) to endpoints.
# https://docs.aws.amazon.com/vpc/latest/privatelink/create-interface-endpoint.html
resource "aws_vpc_security_group_ingress_rule" "https_from_ec2_sg01" {
  security_group_id            = aws_security_group.shinjuku_vpce_sg01.id
  referenced_security_group_id = aws_security_group.shinjuku_ec2_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
# ^^^ added by Lonnie Hodges on 2026-01-19

############################################
# RDS Subnet Group
############################################

# Explanation: RDS hides in private subnets like the Rebel base on Hoth—cold, quiet, and not public.
resource "aws_db_subnet_group" "shinjuku_rds_subnet_group01" {
  name       = "${local.name_prefix}-rds-subnet-group01"
  subnet_ids = aws_subnet.shinjuku_private_subnets[*].id

  tags = {
    Name = "${local.name_prefix}-rds-subnet-group01"
  }
}

############################################
# RDS Instance (MySQL)
############################################
# added by Lonnie Hodges on 2026-01-20
data "aws_ssm_parameter" "shinjuku_db_password_ssm01" {
  name            = "db_password"
  with_decryption = true
}

# Explanation: This is the holocron of state—your relational data lives here, not on the EC2.
resource "aws_db_instance" "shinjuku_rds01" {
  identifier        = "${local.name_prefix}-rds01"
  engine            = var.db_engine
  instance_class    = var.db_instance_class
  allocated_storage = 20
  db_name           = var.db_name
  username          = var.db_username
  password          = data.aws_ssm_parameter.shinjuku_db_password_ssm01.value

  db_subnet_group_name   = aws_db_subnet_group.shinjuku_rds_subnet_group01.name
  vpc_security_group_ids = [aws_security_group.shinjuku_rds_sg01.id]

  publicly_accessible = false
  skip_final_snapshot = true

  # added by Lonnie Hodges
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery", "iam-db-auth-error"]

  # TODO: student sets multi_az / backups / monitoring as stretch goals

  tags = {
    Name = "${local.name_prefix}-rds01"
  }
}

############################################
# IAM Role + Instance Profile for EC2
############################################

# added by Lonnie Hodges
resource "aws_iam_policy" "policy_ec2_read_secret" {
  name        = "read_specific_secret"
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
        "Resource" : "arn:aws:secretsmanager:ap-northeast-1:746669200167:secret:shinjuku/rds/mysql*"
      }
    ]
  })
}
# added by Lonnie Hodges

# Explanation: Shinjuku refuses to carry static keys—this role lets EC2 assume permissions safely.
resource "aws_iam_role" "shinjuku_ec2_role01" {
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
resource "aws_iam_role_policy_attachment" "shinjuku_ec2_ssm_attach" {
  role       = aws_iam_role.shinjuku_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# added by Lonnie Hodges on 2026-01-19
# COMMENTED OUT to use least privilege 
# # Explanation: EC2 must read secrets/params during recovery—give it access (students should scope it down).
# resource "aws_iam_role_policy_attachment" "shinjuku_ec2_secrets_attach" {
#   role       = aws_iam_role.shinjuku_ec2_role01.name
#   policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite" # TODO: student replaces w/ least privilege
# }

# Explanation: CloudWatch logs are the “ship’s black box”—you need them when things explode.
resource "aws_iam_role_policy_attachment" "shinjuku_ec2_cw_attach" {
  role       = aws_iam_role.shinjuku_ec2_role01.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Explanation: Instance profile is the harness that straps the role onto the EC2 like bandolier ammo.
resource "aws_iam_instance_profile" "shinjuku_instance_profile01" {
  name = "${local.name_prefix}-instance-profile01"
  role = aws_iam_role.shinjuku_ec2_role01.name
}

# added by Lonnie Hodges on 2026-01-19
############################################
# Least-Privilege IAM (BONUS A)
############################################

# Explanation: Shinjuku doesn’t hand out the Falcon keys—this policy scopes reads to your lab paths only.
resource "aws_iam_policy" "shinjuku_leastpriv_read_params01" {
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
          "arn:aws:ssm:${data.aws_region.shinjuku_region01.region}:${data.aws_caller_identity.shinjuku_self01.account_id}:parameter/lab/db/*"
        ]
      }
    ]
  })
}

# Explanation: shinjuku only opens *this* vault—GetSecretValue for only your secret (not the whole planet).
resource "aws_iam_policy" "shinjuku_leastpriv_read_secret01" {
  name        = "${local.name_prefix}-lp-secrets-read01"
  description = "Least-privilege read for the lab DB secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadOnlyLabSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = local.shinjuku_secret_arn_guess
      }
    ]
  })
}

# Explanation: When the Falcon logs scream, this lets shinjuku ship logs to CloudWatch without giving away the Death Star plans.
resource "aws_iam_policy" "shinjuku_leastpriv_cwlogs01" {
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
          "logs:DescribeLogStreams",
          "logs:DescribeDeliverySources"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.shinjuku_log_group01.arn}:*"
        ]
      }
    ]
  })
}

# Explanation: Attach the scoped policies—shinjuku loves power, but only the safe kind.
resource "aws_iam_role_policy_attachment" "shinjuku_attach_lp_params01" {
  role       = aws_iam_role.shinjuku_ec2_role01.name
  policy_arn = aws_iam_policy.shinjuku_leastpriv_read_params01.arn
}

resource "aws_iam_role_policy_attachment" "shinjuku_attach_lp_secret01" {
  role       = aws_iam_role.shinjuku_ec2_role01.name
  policy_arn = aws_iam_policy.shinjuku_leastpriv_read_secret01.arn
}

resource "aws_iam_role_policy_attachment" "shinjuku_attach_lp_cwlogs01" {
  role       = aws_iam_role.shinjuku_ec2_role01.name
  policy_arn = aws_iam_policy.shinjuku_leastpriv_cwlogs01.arn
}
# ^^^ added by Lonnie Hodges on 2026-01-19


############################################
# EC2 Instance (App Host)
############################################

# Explanation: This is your “Han Solo box”—it talks to RDS and complains loudly when the DB is down.
# resource "aws_instance" "shinjuku_ec201" {
#   ami                    = var.ec2_ami_id
#   instance_type          = var.ec2_instance_type
#   subnet_id              = aws_subnet.shinjuku_private_subnets[0].id
#   vpc_security_group_ids = [aws_security_group.shinjuku_ec2_sg01.id]
#   iam_instance_profile   = aws_iam_instance_profile.shinjuku_instance_profile01.name

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

# Explanation: Shinjuku hates exposure—private subnets keep your compute off the public holonet.
resource "aws_instance" "shinjuku_ec201_private_bonus" {
  ami                    = var.ec2_ami_id
  instance_type          = var.ec2_instance_type
  subnet_id              = aws_subnet.shinjuku_private_subnets[0].id
  vpc_security_group_ids = [aws_security_group.shinjuku_ec2_sg01.id]
  iam_instance_profile   = aws_iam_instance_profile.shinjuku_instance_profile01.name

  # TODO: Students should remove/disable SSH inbound rules entirely and rely on SSM.
  # TODO: Students add user_data that installs app + CW agent; for true hard mode use a baked AMI.
  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name = "${local.name_prefix}-ec201-private"
  }
}

############################################
# Parameter Store (SSM Parameters)
############################################

# Explanation: Parameter Store is Shinjuku’s map—endpoints and config live here for fast recovery.
resource "aws_ssm_parameter" "shinjuku_db_endpoint_param" {
  name  = "/lab/db/endpoint"
  type  = "String"
  value = aws_db_instance.shinjuku_rds01.address

  tags = {
    Name = "${local.name_prefix}-param-db-endpoint"
  }
}

# Explanation: Ports are boring, but even Wookiees need to know which door number to kick in.
resource "aws_ssm_parameter" "shinjuku_db_port_param" {
  name  = "/lab/db/port"
  type  = "String"
  value = tostring(aws_db_instance.shinjuku_rds01.port)

  tags = {
    Name = "${local.name_prefix}-param-db-port"
  }
}

# Explanation: DB name is the label on the crate—without it, you’re rummaging in the dark.
resource "aws_ssm_parameter" "shinjuku_db_name_param" {
  name  = "/lab/db/name"
  type  = "String"
  value = var.db_name

  tags = {
    Name = "${local.name_prefix}-param-db-name"
  }
}

############################################
# Secrets Manager (DB Credentials)
############################################

# Explanation: Secrets Manager is Shinjuku’s locked holster—credentials go here, not in code.
resource "aws_secretsmanager_secret" "shinjuku_db_secret01" {
  name = "${local.name_prefix}/rds/mysql"
  # added by Lonnie Hodges
  # When I run terraform destroy, I want to immediately destroy the secret.
  recovery_window_in_days = 0
}



# Explanation: Secret payload—students should align this structure with their app (and support rotation later).
resource "aws_secretsmanager_secret_version" "shinjuku_db_secret_version01" {
  secret_id = aws_secretsmanager_secret.shinjuku_db_secret01.id

  secret_string = jsonencode({
    username = var.db_username
    password = data.aws_ssm_parameter.shinjuku_db_password_ssm01.value
    host     = aws_db_instance.shinjuku_rds01.address
    port     = aws_db_instance.shinjuku_rds01.port
    dbname   = var.db_name
  })
}

############################################
# CloudWatch Logs (Log Group)
############################################

# Explanation: When the Falcon is on fire, logs tell you *which* wire sparked—ship them centrally.
resource "aws_cloudwatch_log_group" "shinjuku_log_group01" {
  name              = "/aws/ec2/${local.name_prefix}-rds-app"
  retention_in_days = 7

  tags = {
    Name = "${local.name_prefix}-log-group01"
  }
}

# added by Lonnie Hodges 2026-01-15
resource "aws_cloudwatch_log_stream" "shinjuku_log_stream01" {
  name           = "${local.name_prefix}-rds-app"
  log_group_name = aws_cloudwatch_log_group.shinjuku_log_group01.name
}

############################################
# Custom Metric + Alarm (Skeleton)
############################################
# Explanation: Metrics are Shinjuku’s growls—when they spike, something is wrong.
# NOTE: Students must emit the metric from app/agent; this just declares the alarm.
# Added by Lonnie Hodges:  https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/aws-services-cloudwatch-metrics.html
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/download-CloudWatch-Agent-on-EC2-Instance-commandline-first.html
resource "aws_cloudwatch_metric_alarm" "shinjuku_db_alarm01" {
  alarm_name          = "${local.name_prefix}-db-connection-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "DBConnectionErrors"
  namespace           = "Lab/RDSApp"
  period              = 300
  statistic           = "Sum"
  threshold           = 3

  alarm_actions = [aws_sns_topic.shinjuku_sns_topic01.arn]

  tags = {
    Name = "${local.name_prefix}-alarm-db-fail"
  }
}

############################################
# SNS (PagerDuty simulation)
############################################

# Explanation: SNS is the distress beacon—when the DB dies, the galaxy (your inbox) must hear about it.
resource "aws_sns_topic" "shinjuku_sns_topic01" {
  name = "${local.name_prefix}-db-incidents"
}

# Explanation: Email subscription = “poor man’s PagerDuty”—still enough to wake you up at 3AM.
resource "aws_sns_topic_subscription" "shinjuku_sns_sub01" {
  topic_arn = aws_sns_topic.shinjuku_sns_topic01.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

############################################
# (Optional but realistic) VPC Endpoints (Skeleton)
############################################

# Explanation: Endpoints keep traffic inside AWS like hyperspace lanes—less exposure, more control.
# TODO: students can add endpoints for SSM, Logs, Secrets Manager if doing “no public egress” variant.
# resource "aws_vpc_endpoint" "shinjuku_vpce_ssm" { ... }

# added by Lonnie Hodges on 2026-01-19
############################################
# VPC Endpoint - S3 (Gateway)
############################################

# Explanation: S3 is the supply depot—without this, your private world starves (updates, artifacts, logs).
resource "aws_vpc_endpoint" "shinjuku_vpce_s3_gw01" {
  vpc_id            = aws_vpc.shinjuku_vpc01.id
  service_name      = "com.amazonaws.${data.aws_region.shinjuku_region01.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.shinjuku_private_rt01.id
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
resource "aws_vpc_endpoint" "shinjuku_vpce_ssm01" {
  vpc_id              = aws_vpc.shinjuku_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.shinjuku_region01.region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shinjuku_private_subnets[*].id
  security_group_ids = [aws_security_group.shinjuku_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-ssm01"
  }
}

# Explanation: ec2messages is the Wookiee messenger—SSM sessions won’t work without it.
resource "aws_vpc_endpoint" "shinjuku_vpce_ec2messages01" {
  vpc_id              = aws_vpc.shinjuku_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.shinjuku_region01.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shinjuku_private_subnets[*].id
  security_group_ids = [aws_security_group.shinjuku_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-ec2messages01"
  }
}

# Explanation: ssmmessages is the holonet channel—Session Manager needs it to talk back.
resource "aws_vpc_endpoint" "shinjuku_vpce_ssmmessages01" {
  vpc_id              = aws_vpc.shinjuku_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.shinjuku_region01.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shinjuku_private_subnets[*].id
  security_group_ids = [aws_security_group.shinjuku_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-ssmmessages01"
  }
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-19
############################################
# VPC Endpoint - CloudWatch Logs (Interface)
############################################

# Explanation: CloudWatch Logs is the ship’s black box—shinjuku wants crash data, always.
resource "aws_vpc_endpoint" "shinjuku_vpce_logs01" {
  vpc_id              = aws_vpc.shinjuku_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.shinjuku_region01.region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shinjuku_private_subnets[*].id
  security_group_ids = [aws_security_group.shinjuku_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-logs01"
  }
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-19
############################################
# VPC Endpoint - Secrets Manager (Interface)
############################################

# Explanation: Secrets Manager is the locked vault—shinjuku doesn't put passwords on sticky notes.
resource "aws_vpc_endpoint" "shinjuku_vpce_secrets01" {
  vpc_id              = aws_vpc.shinjuku_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.shinjuku_region01.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shinjuku_private_subnets[*].id
  security_group_ids = [aws_security_group.shinjuku_vpce_sg01.id]

  tags = {
    Name = "${local.name_prefix}-vpce-secrets01"
  }
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-19
############################################
# Optional: VPC Endpoint - KMS (Interface)
############################################

# Explanation: KMS is the encryption kyber crystal—shinjuku prefers locked doors AND locked safes.
resource "aws_vpc_endpoint" "shinjuku_vpce_kms01" {
  vpc_id              = aws_vpc.shinjuku_vpc01.id
  service_name        = "com.amazonaws.${data.aws_region.shinjuku_region01.region}.kms"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shinjuku_private_subnets[*].id
  security_group_ids = [aws_security_group.shinjuku_vpce_sg01.id]

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
resource "aws_security_group" "shinjuku_alb_sg01" {
  name        = "${var.project_name}-alb-sg01"
  description = "ALB security group"
  vpc_id      = aws_vpc.shinjuku_vpc01.id

  # TODO: students add inbound 80/443 from 0.0.0.0/0
  # TODO: students set outbound to target group port (usually 80) to private targets

  tags = {
    Name = "${var.project_name}-alb-sg01"
  }
}

# No longer needed. INternet users should not be able access the ALB
# # Explanation: shinjuku only opens the hangar door — allow ALB -> EC2 on app port (e.g., 80).
# resource "aws_vpc_security_group_ingress_rule" "shinjuku_ec2_ingress_from_internet" {
#   security_group_id = aws_security_group.shinjuku_alb_sg01.id
#   cidr_ipv4         = "0.0.0.0/0"
#   ip_protocol       = "tcp"
#   from_port         = 80
#   to_port           = 80

#   # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
# }

# # chobase only opens the hangar door — allow ALB -> EC2 on app port (e.g., 443).
# resource "aws_vpc_security_group_ingress_rule" "shinjuku_tls_ec2_ingress_from_internet" {
#   #security_group_id = aws_security_group.shinjuku_alb_sg01.id
#   security_group_id = aws_security_group.shinjuku_alb_sg01.id
#   cidr_ipv4         = "0.0.0.0/0"
#   ip_protocol       = "tcp"
#   from_port         = 443
#   to_port           = 443

#   # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
# }

# Explanation: shinjuku only opens the hangar door — allow ALB -> EC2 on app port (e.g., 443).
resource "aws_vpc_security_group_egress_rule" "shinjuku_egress_to_ec2" {
  security_group_id            = aws_security_group.shinjuku_alb_sg01.id
  referenced_security_group_id = aws_security_group.shinjuku_ec2_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80

  # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
}

# Explanation: shinjuku only opens the hangar door — allow ALB -> EC2 on app port (e.g., 443).
resource "aws_vpc_security_group_egress_rule" "shinjuku_tls_egress_to_ec2" {
  security_group_id            = aws_security_group.shinjuku_alb_sg01.id
  referenced_security_group_id = aws_security_group.shinjuku_ec2_sg01.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  # TODO: students ensure EC2 app listens on this port (or change to 8080, etc.)
}


############################################
# Application Load Balancer
############################################

# Explanation: The ALB is your public customs checkpoint — it speaks TLS and forwards to private targets.
resource "aws_lb" "shinjuku_alb01" {
  name               = "${var.project_name}-alb01"
  load_balancer_type = "application"
  internal           = false

  security_groups = [aws_security_group.shinjuku_alb_sg01.id]
  subnets         = aws_subnet.shinjuku_public_subnets[*].id

  # TODO: students can enable access logs to S3 as a stretch goal
  # Explanation: Turn on access logs—Shinjuku wants receipts when something goes wrong.
  # added by Lonnie Hodges on 2026-01-20
  access_logs {
    bucket  = aws_s3_bucket.shinjuku_alb_logs_bucket01[0].bucket
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

# Explanation: Target groups are shinjuku's "who do I forward to?” list — private EC2 lives here.
resource "aws_lb_target_group" "shinjuku_tg01" {
  name     = "${var.project_name}-tg01"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.shinjuku_vpc01.id

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

# Explanation: shinjuku personally introduces the ALB to the private EC2 — “this is my friend, don’t shoot.”
resource "aws_lb_target_group_attachment" "shinjuku_tg_attach01" {
  target_group_arn = aws_lb_target_group.shinjuku_tg01.arn
  target_id        = aws_instance.shinjuku_ec201_private_bonus.id
  port             = 80

  # TODO: students ensure EC2 security group allows inbound from ALB SG on this port (rule above)
}

# resource "aws_lb_target_group_attachment" "shinjuku_tg_attach02" {
#   target_group_arn = aws_lb_target_group.shinjuku_tg01.arn
#   target_id        = aws_instance.shinjuku_ec201.id
#   port             = 80

#   # TODO: students ensure EC2 security group allows inbound from ALB SG on this port (rule above)
# }

##################################################################
# ACM Certificate (TLS) for app.echobase.click and echobase.click
##################################################################

# Explanation: TLS is the diplomatic passport — browsers trust you, and shinjuku stops growling at plaintext.
resource "aws_acm_certificate" "shinjuku_acm_cert01" {
  domain_name       = local.shinjuku_app_fqdn
  validation_method = var.certificate_validation_method

  # TODO: students can add subject_alternative_names like var.domain_name if desired
  # added by Lonnie Hodges on 2026-01-21
  subject_alternative_names = [local.shinjuku_fqdn]

  tags = {
    Name = "${var.project_name}-acm-cert01"
  }
}

resource "aws_acm_certificate" "shinjuku_cf_acm_cert01" {
  provider          = aws.acm_useast1
  domain_name       = local.shinjuku_app_fqdn
  validation_method = var.certificate_validation_method

  # TODO: students can add subject_alternative_names like var.domain_name if desired
  # added by Lonnie Hodges on 2026-01-25
  subject_alternative_names = [local.shinjuku_fqdn]

  tags = {
    Name = "${var.project_name}-cf-acm-cert01"
  }
}

# Explanation: DNS validation records are the “prove you own the planet” ritual — Route53 makes this elegant.
# TODO: students implement aws_route53_record(s) if they manage DNS in Route53.
# resource "aws_route53_record" "shinjuku_acm_validation" { ... }

resource "aws_route53_record" "shinjuku_apex_alias01" {
  zone_id = var.route53_hosted_zone_id
  name    = local.shinjuku_fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.shinjuku_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.shinjuku_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "shinjuku_app_alias01" {
  zone_id = var.route53_hosted_zone_id
  name    = local.shinjuku_app_fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.shinjuku_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.shinjuku_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

# added by Lonnie Hodges on 2026-02-02
resource "aws_route53_record" "shinjuku_apex_ipv6_alias01" {
  zone_id = var.route53_hosted_zone_id
  name    = local.shinjuku_fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.shinjuku_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.shinjuku_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "shinjuku_app_ipv6_alias01" {
  zone_id = var.route53_hosted_zone_id
  name    = local.shinjuku_app_fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.shinjuku_cf01.domain_name
    zone_id                = aws_cloudfront_distribution.shinjuku_cf01.hosted_zone_id
    evaluate_target_health = false
  }
}
# ^^^ added by Lonnie Hodges on 2026-02-02

data "aws_route53_zone" "shinjuku_click" {
  #zone_id = "Z0828030PI6PCZKRD9SW" for echobase.click
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "shinjuku_acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.shinjuku_acm_cert01.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.shinjuku_click.zone_id
}

# Explanation: Once validated, ACM becomes the “green checkmark” — until then, ALB HTTPS won’t work.
resource "aws_acm_certificate_validation" "shinjuku_acm_validation01" {
  certificate_arn = aws_acm_certificate.shinjuku_acm_cert01.arn

  # TODO: if using DNS validation, students must pass validation_record_fqdns
  validation_record_fqdns = [for record in aws_route53_record.shinjuku_acm_validation : record.fqdn]
}

# added by Lonnie Hodges on 2026-01-25
# TESTING
resource "aws_route53_record" "shinjuku_cf_acm_validation" {
  provider = aws.acm_useast1
  for_each = {
    for dvo in aws_acm_certificate.shinjuku_cf_acm_cert01.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.shinjuku_click.zone_id
}

# Explanation: Once validated, ACM becomes the “green checkmark” — until then, ALB HTTPS won’t work.
resource "aws_acm_certificate_validation" "shinjuku_cf_acm_validation01" {
  provider        = aws.acm_useast1
  certificate_arn = aws_acm_certificate.shinjuku_cf_acm_cert01.arn

  # TODO: if using DNS validation, students must pass validation_record_fqdns
  validation_record_fqdns = [for record in aws_route53_record.shinjuku_cf_acm_validation : record.fqdn]
}

############################################
# ALB Listeners: HTTP -> HTTPS redirect, HTTPS -> TG
############################################

# Explanation: HTTP listener is the decoy airlock — it redirects everyone to the secure entrance.
resource "aws_lb_listener" "shinjuku_http_listener01" {
  load_balancer_arn = aws_lb.shinjuku_alb01.arn
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

# Explanation: HTTPS listener is the real hangar bay — TLS terminates here, then traffic goes to private targets.
resource "aws_lb_listener" "shinjuku_https_listener01" {
  load_balancer_arn = aws_lb.shinjuku_alb01.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.shinjuku_acm_validation01.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shinjuku_tg01.arn
  }

  depends_on = [aws_acm_certificate_validation.shinjuku_acm_validation01]
}
# ^^^ added by Lonnie Hodges on 2026-01-19

# added by Lonnie Hodges on 2026-01-20
############################################
# WAFv2 Web ACL (Basic managed rules)
############################################

# # Explanation: WAF is the shield generator — it blocks the cheap blaster fire before it hits your ALB.
# resource "aws_wafv2_web_acl" "shinjuku_waf01" {
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
# resource "aws_wafv2_web_acl_association" "shinjuku_waf_assoc01" {
#   count = var.enable_waf ? 1 : 0

#   resource_arn = aws_lb.shinjuku_alb01.arn
#   web_acl_arn  = aws_wafv2_web_acl.shinjuku_waf01[0].arn
# }
# # ^^^ added by Lonnie Hodges on 2026-01-20

# added by Lonnie Hodges on 2026-01-20
############################################
# CloudWatch Alarm: ALB 5xx -> SNS
############################################

# Explanation: When the ALB starts throwing 5xx, that’s the Falcon coughing — page the on-call Wookiee.
resource "aws_cloudwatch_metric_alarm" "shinjuku_alb_5xx_alarm01" {
  alarm_name          = "${var.project_name}-alb-5xx-alarm01"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alb_5xx_evaluation_periods
  threshold           = var.alb_5xx_threshold
  period              = var.alb_5xx_period_seconds
  statistic           = "Sum"

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_ELB_5XX_Count"

  dimensions = {
    LoadBalancer = aws_lb.shinjuku_alb01.arn_suffix
  }

  alarm_actions = [aws_sns_topic.shinjuku_sns_topic02.arn]

  tags = {
    Name = "${var.project_name}-alb-5xx-alarm01"
  }
}

# added by Lonnie Hodges on 2026-01-23
# Explanation: SNS is the distress beacon—when the DB dies, the galaxy (your inbox) must hear about it.
resource "aws_sns_topic" "shinjuku_sns_topic02" {
  name = "${local.name_prefix}-alb-5xx-incidents"
}

# Explanation: Email subscription = “poor man’s PagerDuty”—still enough to wake you up at 3AM.
resource "aws_sns_topic_subscription" "shinjuku_sns_sub02" {
  topic_arn = aws_sns_topic.shinjuku_sns_topic02.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

############################################
# CloudWatch Dashboard (Skeleton)
############################################

# Explanation: Dashboards are your cockpit HUD — shinjuku wants dials, not vibes.
resource "aws_cloudwatch_dashboard" "shinjuku_dashboard01" {
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
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.shinjuku_alb01.arn_suffix],
            [".", "HTTPCode_ELB_5XX_Count", ".", aws_lb.shinjuku_alb01.arn_suffix]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Shinjuku ALB: Requests + 5XX"
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
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.shinjuku_alb01.arn_suffix]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Shinjuku ALB: Target Response Time"
        }
      }
    ]
  })
}

############################################
# S3 bucket for ALB access logs
############################################

# Explanation: This bucket is shinjuku's log vault—every visitor to the ALB leaves footprints here.
resource "aws_s3_bucket" "shinjuku_alb_logs_bucket01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = "${var.project_name}-alb-logs-${data.aws_caller_identity.shinjuku_self01.account_id}"

  force_destroy = true

  tags = {
    Name = "${var.project_name}-alb-logs-bucket01"
  }
}

# Explanation: Block public access—shinjuku does not publish the ship’s black box to the galaxy.
resource "aws_s3_bucket_public_access_block" "shinjuku_alb_logs_pab01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket                  = aws_s3_bucket.shinjuku_alb_logs_bucket01[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Bucket ownership controls prevent log delivery chaos—shinjuku likes clean chain-of-custody.
resource "aws_s3_bucket_ownership_controls" "shinjuku_alb_logs_owner01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.shinjuku_alb_logs_bucket01[0].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Explanation: TLS-only—shinjuku growls at plaintext and throws it out an airlock.
resource "aws_s3_bucket_policy" "shinjuku_alb_logs_policy01" {
  count = var.enable_alb_access_logs ? 1 : 0

  bucket = aws_s3_bucket.shinjuku_alb_logs_bucket01[0].id

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
          aws_s3_bucket.shinjuku_alb_logs_bucket01[0].arn,
          "${aws_s3_bucket.shinjuku_alb_logs_bucket01[0].arn}/*"
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
        Resource = "${aws_s3_bucket.shinjuku_alb_logs_bucket01[0].arn}/${var.alb_access_logs_prefix}/AWSLogs/${data.aws_caller_identity.shinjuku_self01.account_id}/*"
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
resource "aws_cloudwatch_log_group" "shinjuku_waf_log_group01" {
  count = var.waf_log_destination == "cloudwatch" ? 1 : 0

  # NOTE: AWS requires WAF log destination names start with aws-waf-logs- (students must not rename this).
  name              = "aws-waf-logs-${var.project_name}-webacl01"
  retention_in_days = var.waf_log_retention_days

  tags = {
    Name = "${var.project_name}-waf-log-group01"
  }
}

# # Explanation: This wire connects the shield generator to the black box—WAF -> CloudWatch Logs.
# resource "aws_wafv2_web_acl_logging_configuration" "shinjuku_waf_logging01" {
#   count = var.enable_waf && var.waf_log_destination == "cloudwatch" ? 1 : 0

#   resource_arn = aws_wafv2_web_acl.shinjuku_waf01[0].arn
#   log_destination_configs = [
#     aws_cloudwatch_log_group.shinjuku_waf_log_group01[0].arn
#   ]

#   # TODO: Students can add redacted_fields (authorization headers, cookies, etc.) as a stretch goal.
#   # redacted_fields { ... }

#   depends_on = [aws_wafv2_web_acl.shinjuku_waf01]
# }

############################################
# Option 2: S3 destination (direct)
############################################

# Explanation: S3 WAF logs are the long-term archive—shinjuku likes receipts that survive dashboards.
resource "aws_s3_bucket" "shinjuku_waf_logs_bucket01" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  bucket = "aws-waf-logs-${var.project_name}-${data.aws_caller_identity.shinjuku_self01.account_id}"

  # added by Lonnie Hodges on 2026-01-21
  force_destroy = true

  tags = {
    Name = "${var.project_name}-waf-logs-bucket01"
  }
}

# Explanation: Public access blocked—WAF logs are not a bedtime story for the entire internet.
resource "aws_s3_bucket_public_access_block" "shinjuku_waf_logs_pab01" {
  count = var.waf_log_destination == "s3" ? 1 : 0

  bucket                  = aws_s3_bucket.shinjuku_waf_logs_bucket01[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# # Explanation: Connect shield generator to archive vault—WAF -> S3.
# resource "aws_wafv2_web_acl_logging_configuration" "shinjuku_waf_logging_s3_01" {
#   count = var.enable_waf && var.waf_log_destination == "s3" ? 1 : 0

#   resource_arn = aws_wafv2_web_acl.shinjuku_waf01[0].arn
#   log_destination_configs = [
#     aws_s3_bucket.shinjuku_waf_logs_bucket01[0].arn
#   ]

#   depends_on = [aws_wafv2_web_acl.shinjuku_waf01]
# }

############################################
# Option 3: Firehose destination (classic “stream then store”)
############################################

# Explanation: Firehose is the conveyor belt—WAF logs ride it to storage (and can fork to SIEM later).
resource "aws_s3_bucket" "shinjuku_firehose_waf_dest_bucket01" {
  count = var.waf_log_destination == "firehose" ? 1 : 0

  bucket = "${var.project_name}-waf-firehose-dest-${data.aws_caller_identity.shinjuku_self01.account_id}"

  # added by Lonnie Hodges on 2026-01-21
  force_destroy = true

  tags = {
    Name = "${var.project_name}-waf-firehose-dest-bucket01"
  }
}

# Explanation: Firehose needs a role—shinjuku doesn't let random droids write into storage.
resource "aws_iam_role" "shinjuku_firehose_role01" {
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
resource "aws_iam_role_policy" "shinjuku_firehose_policy01" {
  count = var.waf_log_destination == "firehose" ? 1 : 0
  name  = "${var.project_name}-firehose-policy01"
  role  = aws_iam_role.shinjuku_firehose_role01[0].id

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
          aws_s3_bucket.shinjuku_firehose_waf_dest_bucket01[0].arn,
          "${aws_s3_bucket.shinjuku_firehose_waf_dest_bucket01[0].arn}/*"
        ]
      }
    ]
  })
}

# Explanation: The delivery stream is the belt itself—logs move from WAF -> Firehose -> S3.
resource "aws_kinesis_firehose_delivery_stream" "shinjuku_waf_firehose01" {
  count       = var.waf_log_destination == "firehose" ? 1 : 0
  name        = "aws-waf-logs-${var.project_name}-firehose01"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.shinjuku_firehose_role01[0].arn
    bucket_arn = aws_s3_bucket.shinjuku_firehose_waf_dest_bucket01[0].arn
    prefix     = "waf-logs/"
  }
}

# Explanation: Connect shield generator to conveyor belt—WAF -> Firehose stream.
# resource "aws_wafv2_web_acl_logging_configuration" "shinjuku_waf_logging_firehose01" {
#   count = var.enable_waf && var.waf_log_destination == "firehose" ? 1 : 0

#   resource_arn = aws_wafv2_web_acl.shinjuku_waf01[0].arn
#   log_destination_configs = [
#     aws_kinesis_firehose_delivery_stream.shinjuku_waf_firehose01[0].arn
#   ]

#   depends_on = [aws_wafv2_web_acl.shinjuku_waf01]
# }
# ^^^ added by Lonnie Hodges on 2026-01-21

# added by Lonnie Hodges on 2026-02-09
############################################
# S3 bucket for CLoudTrail
############################################

# Explanation: This bucket is shinjuku's log vault—every visitor to the ALB leaves footprints here.
resource "aws_s3_bucket" "shinjuku_cloudtrail_logs_bucket01" {
  count = var.enable_cloudtrail_logs ? 1 : 0

  bucket = "${var.project_name}-cloudtrail-logs-${data.aws_caller_identity.shinjuku_self01.account_id}"

  force_destroy = true

  tags = {
    Name = "${var.project_name}-cloudtrail-logs-bucket01"
  }
}

# Explanation: Block public access—shinjuku does not publish the ship’s black box to the galaxy.
resource "aws_s3_bucket_public_access_block" "shinjuku_cloudtrail_logs_pab01" {
  count = var.enable_cloudtrail_logs ? 1 : 0

  bucket                  = aws_s3_bucket.shinjuku_cloudtrail_logs_bucket01[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Bucket ownership controls prevent log delivery chaos—shinjuku likes clean chain-of-custody.
resource "aws_s3_bucket_ownership_controls" "shinjuku_cloudtrail_logs_owner01" {
  count = var.enable_cloudtrail_logs ? 1 : 0

  bucket = aws_s3_bucket.shinjuku_cloudtrail_logs_bucket01[0].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Explanation: TLS-only—shinjuku growls at plaintext and throws it out an airlock.
resource "aws_s3_bucket_policy" "shinjuku_cloudtrail_logs_policy01" {
  count = var.enable_cloudtrail_logs ? 1 : 0

  bucket = aws_s3_bucket.shinjuku_cloudtrail_logs_bucket01[0].id

  # NOTE: This is a skeleton. Students may need to adjust for region/account specifics.
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AWSCloudTrailAclCheck20150319",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "cloudtrail.amazonaws.com"
        },
        "Action" : "s3:GetBucketAcl",
        "Resource" : "arn:aws:s3:::shinjuku-cloudtrail-logs-${data.aws_caller_identity.shinjuku_self01.account_id}",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.shinjuku_self01.account_id}:trail/management-events"
          }
        }
      },
      {
        "Sid" : "AWSCloudTrailWrite",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "cloudtrail.amazonaws.com"
        },
        "Action" : "s3:PutObject",
        "Resource" : "arn:aws:s3:::shinjuku-cloudtrail-logs-${data.aws_caller_identity.shinjuku_self01.account_id}/${var.cloudtrail_logs_prefix}/AWSLogs/${data.aws_caller_identity.shinjuku_self01.account_id}/*",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : "arn:aws:cloudtrail:${var.aws_region}:${data.aws_caller_identity.shinjuku_self01.account_id}:trail/management-events",
            "s3:x-amz-acl" : "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

############################################
# CloudTrail
############################################
resource "aws_cloudtrail" "shinjuku_cloudtrail01" {
  depends_on = [aws_s3_bucket_policy.shinjuku_cloudtrail_logs_policy01]

  name                          = "management-events"
  s3_bucket_name                = aws_s3_bucket.shinjuku_cloudtrail_logs_bucket01[0].id
  s3_key_prefix                 = "cloudtrail-logs"
  include_global_service_events = true
  enable_logging                = true
  is_multi_region_trail         = true
}

# added by Lonnie Hodges on 2026-02-09
############################################
# Flow Log
############################################
resource "aws_flow_log" "shinjuku_flowlog01" {
  log_destination          = aws_s3_bucket.shinjuku_flow_logs_bucket01[0].arn
  log_destination_type     = "s3"
  log_format               = "$${version} $${resource-type} $${account-id} $${tgw-id} $${tgw-attachment-id} $${tgw-src-vpc-account-id} $${tgw-dst-vpc-account-id} $${tgw-src-vpc-id} $${tgw-dst-vpc-id} $${tgw-pair-attachment-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${log-status} $${flow-direction}"
  traffic_type             = "ALL"
  transit_gateway_id       = aws_ec2_transit_gateway.shinjuku_tgw01.id
  max_aggregation_interval = 60

  destination_options {
    file_format        = "plain-text"
    per_hour_partition = true
  }
}

############################################
# S3 bucket for Flow Log
############################################
# Explanation: This bucket is shinjuku's log vault—every visitor to the ALB leaves footprints here.
resource "aws_s3_bucket" "shinjuku_flow_logs_bucket01" {
  count = var.enable_flow_logs ? 1 : 0

  bucket = "${var.project_name}-flow-logs-${data.aws_caller_identity.shinjuku_self01.account_id}"

  force_destroy = true

  tags = {
    Name = "${var.project_name}-flow-logs-bucket01"
  }
}

# Explanation: Block public access—shinjuku does not publish the ship’s black box to the galaxy.
resource "aws_s3_bucket_public_access_block" "shinjuku_flow_logs_pab01" {
  count = var.enable_flow_logs ? 1 : 0

  bucket                  = aws_s3_bucket.shinjuku_flow_logs_bucket01[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Explanation: Bucket ownership controls prevent log delivery chaos—shinjuku likes clean chain-of-custody.
resource "aws_s3_bucket_ownership_controls" "shinjuku_flow_logs_owner01" {
  count = var.enable_flow_logs ? 1 : 0

  bucket = aws_s3_bucket.shinjuku_flow_logs_bucket01[0].id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Explanation: TLS-only—shinjuku growls at plaintext and throws it out an airlock.
resource "aws_s3_bucket_policy" "shinjuku_flow_logs_policy01" {
  count = var.enable_flow_logs ? 1 : 0

  bucket = aws_s3_bucket.shinjuku_flow_logs_bucket01[0].id

  # NOTE: This is a skeleton. Students may need to adjust for region/account specifics.
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Id" : "AWSLogDeliveryWrite20150319",
    "Statement" : [
      {
        "Sid" : "AWSLogDeliveryWrite1",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "delivery.logs.amazonaws.com"
        },
        "Action" : "s3:PutObject",
        "Resource" : "${aws_s3_bucket.shinjuku_flow_logs_bucket01[0].arn}/AWSLogs/${data.aws_caller_identity.shinjuku_self01.account_id}/*",
        "Condition" : {
          "StringEquals" : {
            "s3:x-amz-acl" : "bucket-owner-full-control",
            "aws:SourceAccount" : "${data.aws_caller_identity.shinjuku_self01.account_id}"
          },
          "ArnLike" : {
            "aws:SourceArn" : "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.shinjuku_self01.account_id}:*"
          }
        }
      },
      {
        "Sid" : "AWSLogDeliveryAclCheck1",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "delivery.logs.amazonaws.com"
        },
        "Action" : "s3:GetBucketAcl",
        "Resource" : "${aws_s3_bucket.shinjuku_flow_logs_bucket01[0].arn}",
        "Condition" : {
          "StringEquals" : {
            "aws:SourceAccount" : "${data.aws_caller_identity.shinjuku_self01.account_id}"
          },
          "ArnLike" : {
            "aws:SourceArn" : "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.shinjuku_self01.account_id}:*"
          }
        }
      }
    ]
  })
}