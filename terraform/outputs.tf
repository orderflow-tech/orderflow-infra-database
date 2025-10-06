output "db_instance_id" {
  description = "ID of the RDS instance"
  value       = aws_db_instance.orderflow.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.orderflow.arn
}

output "db_instance_endpoint" {
  description = "Connection endpoint for the RDS instance"
  value       = aws_db_instance.orderflow.endpoint
}

output "db_instance_address" {
  description = "Hostname of the RDS instance"
  value       = aws_db_instance.orderflow.address
}

output "db_instance_port" {
  description = "Port of the RDS instance"
  value       = aws_db_instance.orderflow.port
}

output "db_instance_name" {
  description = "Name of the database"
  value       = aws_db_instance.orderflow.db_name
}

output "db_instance_username" {
  description = "Master username for the database"
  value       = aws_db_instance.orderflow.username
  sensitive   = true
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_security_group_id" {
  description = "ID of the security group for the RDS instance"
  value       = aws_security_group.rds.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.orderflow.name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.database.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.database.cidr_block
}

output "subnet_ids" {
  description = "IDs of the database subnets"
  value       = aws_subnet.database_private[*].id
}

output "read_replica_endpoint" {
  description = "Connection endpoint for the read replica (if created)"
  value       = var.create_read_replica ? aws_db_instance.orderflow_replica[0].endpoint : null
}

output "connection_string" {
  description = "PostgreSQL connection string (without password)"
  value       = "postgresql://${aws_db_instance.orderflow.username}@${aws_db_instance.orderflow.address}:${aws_db_instance.orderflow.port}/${aws_db_instance.orderflow.db_name}"
  sensitive   = true
}

# Bastion Host Outputs
output "bastion_host_public_ip" {
  description = "Public IP of the bastion host"
  value       = var.create_bastion_host && var.bastion_public_key != "" ? aws_instance.bastion[0].public_ip : null
}

output "bastion_host_ssh_command" {
  description = "SSH command to connect to bastion host"
  value       = var.create_bastion_host && var.bastion_public_key != "" ? "ssh -i ~/.ssh/orderflow-bastion ec2-user@${aws_instance.bastion[0].public_ip}" : null
}

output "database_tunnel_command" {
  description = "SSH tunnel command for database access"
  value       = var.create_bastion_host && var.bastion_public_key != "" ? "ssh -i ~/.ssh/orderflow-bastion -L 5432:${aws_db_instance.orderflow.address}:5432 ec2-user@${aws_instance.bastion[0].public_ip}" : null
}
