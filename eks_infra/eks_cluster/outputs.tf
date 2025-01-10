# output "public_route_table_ids" {
#   description = "List of IDs of public route tables"
#   value       = aws_route_table.public.*.id
# }

# output "private_route_table_ids" {
#   description = "List of IDs of private route tables"
#   value       = aws_route_table.private.*.id
# }

# Outputs for the VPC and subnets
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "private_subnets" {
  value = module.vpc.private_subnets
}
