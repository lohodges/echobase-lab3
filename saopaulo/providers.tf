provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "acm_useast1"
  region = var.aws_region_acm
}