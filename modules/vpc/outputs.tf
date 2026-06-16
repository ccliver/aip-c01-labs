output "vpc_id" {
  description = "ID of the created VPC"
  value       = null # TODO: replace with aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = [] # TODO: replace with aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = [] # TODO: replace with aws_subnet.public[*].id
}
