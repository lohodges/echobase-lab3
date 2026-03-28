provider "aws" {
  region = "ap-northeast-1"
  alias  = "tokyo"
}

provider "aws" {
  region = "sa-east-1"
  alias  = "saopaulo"
}

data "terraform_remote_state" "tokyo" {
  backend = "local"
  config  = { path = "../tokyo/terraform.tfstate" }
}

data "terraform_remote_state" "saopaulo" {
  backend = "local"
  config  = { path = "../saopaulo/terraform.tfstate" }
}

# Explanation: Liberdade accepts the corridor from Shinjuku—permissions are explicit, not assumed.
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "liberdade_accept_peer01" {
  provider                      = aws.saopaulo
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01.id
  tags                          = { Name = "liberdade-accept-peer01" }
}

resource "aws_ec2_transit_gateway_route" "liberdade_to_tokyo_via_peer01" {
  provider                       = aws.saopaulo
  destination_cidr_block         = "10.124.0.0/16"
  transit_gateway_route_table_id = data.terraform_remote_state.saopaulo.outputs.liberdade_tgw01_default_route_table_id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment_accepter.liberdade_accept_peer01.id
}

# Explanation: Shinjuku opens a corridor request to Liberdade—compute may travel, data may not.
resource "aws_ec2_transit_gateway_peering_attachment" "shinjuku_to_liberdade_peer01" {
  provider                = aws.tokyo
  transit_gateway_id      = data.terraform_remote_state.tokyo.outputs.shinjuku_tgw01_id
  peer_region             = "sa-east-1"
  peer_transit_gateway_id = data.terraform_remote_state.saopaulo.outputs.liberdade_tgw01_id
  tags                    = { Name = "shinjuku-to-liberdade-peer01" }
}

resource "aws_ec2_transit_gateway_route" "shinjuku_to_sp_via_peer01" {
  provider                       = aws.tokyo
  destination_cidr_block         = "10.136.0.0/16"
  transit_gateway_route_table_id = data.terraform_remote_state.tokyo.outputs.shinjuku_tgw01_default_route_table_id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.shinjuku_to_liberdade_peer01.id
  depends_on                     = [aws_ec2_transit_gateway_peering_attachment_accepter.liberdade_accept_peer01]
}