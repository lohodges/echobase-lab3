output "liberdade_tgw01_id" {
  value = aws_ec2_transit_gateway.liberdade_tgw01.id
}
output "liberdade_tgw01_default_route_table_id" {
  value = aws_ec2_transit_gateway.liberdade_tgw01.association_default_route_table_id
}
