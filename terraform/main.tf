terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket = "orderflow-terraform-state"
    key    = "database/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "OrderFlow"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "Database"
    }
  }
}

# Data source para obter as zonas de disponibilidade
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC para o banco de dados
resource "aws_vpc" "database" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-database-vpc-${var.environment}"
  }
}

# Subnets privadas para o RDS
resource "aws_subnet" "database_private" {
  count             = var.database_subnet_count
  vpc_id            = aws_vpc.database.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-database-subnet-${count.index + 1}-${var.environment}"
    Type = "private"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "database" {
  vpc_id = aws_vpc.database.id

  tags = {
    Name = "${var.project_name}-database-igw-${var.environment}"
  }
}

# Route Table
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.database.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.database.id
  }

  tags = {
    Name = "${var.project_name}-database-rt-${var.environment}"
  }
}

# Route Table Association
resource "aws_route_table_association" "database" {
  count          = var.database_subnet_count
  subnet_id      = aws_subnet.database_private[count.index].id
  route_table_id = aws_route_table.database.id
}

# DB Subnet Group
resource "aws_db_subnet_group" "orderflow" {
  name       = "${var.project_name}-db-subnet-group-${var.environment}"
  subnet_ids = aws_subnet.database_private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group-${var.environment}"
  }
}

# Security Group para RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg-${var.environment}"
  description = "Security group for OrderFlow RDS instance"
  vpc_id      = aws_vpc.database.id

  # Ingress rule para PostgreSQL
  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Ingress rule para permitir acesso do Bastion Host
  ingress {
    description     = "PostgreSQL from Bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.create_bastion_host ? [aws_security_group.bastion.id] : []
  }

  # Ingress rule para permitir acesso do EKS (será configurado via peering)
  ingress {
    description = "PostgreSQL from EKS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg-${var.environment}"
  }
}

# Gerar senha aleatória para o banco de dados
resource "random_password" "db_password" {
  length  = 32
  special = true
  # Evitar caracteres que podem causar problemas em connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Armazenar credenciais no Secrets Manager
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-db-credentials-${var.environment}"
  description = "Database credentials for OrderFlow RDS instance"

  tags = {
    Name = "${var.project_name}-db-credentials-${var.environment}"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "postgres"
    host     = aws_db_instance.orderflow.address
    port     = aws_db_instance.orderflow.port
    dbname   = var.db_name
  })
}

# Parameter Group para PostgreSQL
resource "aws_db_parameter_group" "orderflow" {
  name   = "${var.project_name}-pg-${var.environment}"
  family = "postgres16"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_duration"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "all"
  }

  # Removed shared_preload_libraries as it's a static parameter that requires restart
  # Can be configured manually after RDS instance is created if needed

  tags = {
    Name = "${var.project_name}-pg-${var.environment}"
  }
}

# Option Group (não necessário para PostgreSQL, mas mantido para consistência)
resource "aws_db_option_group" "orderflow" {
  name                     = "${var.project_name}-og-${var.environment}"
  option_group_description = "Option group for OrderFlow RDS instance"
  engine_name              = "postgres"
  major_engine_version     = "16"

  tags = {
    Name = "${var.project_name}-og-${var.environment}"
  }
}

# RDS Instance
resource "aws_db_instance" "orderflow" {
  identifier = "${var.project_name}-db-${var.environment}"

  # Engine configuration
  engine               = "postgres"
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type         = "gp3"
  storage_encrypted    = true
  # iops removed - not needed for small storage sizes and gp3 provides baseline performance

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.orderflow.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = var.publicly_accessible

  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.orderflow.name
  option_group_name    = aws_db_option_group.orderflow.name

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Monitoring (simplified for AWS Lab)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  # monitoring_interval removed due to IAM restrictions in AWS Lab
  # monitoring_role_arn removed due to IAM restrictions in AWS Lab
  performance_insights_enabled    = true
  performance_insights_retention_period = 7

  # High availability
  multi_az               = var.multi_az
  deletion_protection    = var.environment == "production"
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.project_name}-db-${var.environment}"
  }

  lifecycle {
    ignore_changes = [
      password,
      final_snapshot_identifier
    ]
  }
}

# IAM Role para Enhanced Monitoring - DISABLED for AWS Lab
# AWS Lab has restricted IAM permissions, so we can't create custom roles
# Enhanced monitoring will be disabled to work within Lab constraints

# resource "aws_iam_role" "rds_monitoring" {
#   name = "${var.project_name}-rds-monitoring-role-${var.environment}"
# 
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "monitoring.rds.amazonaws.com"
#         }
#       }
#     ]
#   })
# 
#   tags = {
#     Name = "${var.project_name}-rds-monitoring-role-${var.environment}"
#   }
# }
# 
# resource "aws_iam_role_policy_attachment" "rds_monitoring" {
#   role       = aws_iam_role.rds_monitoring.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
# }

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.project_name}-db-cpu-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.orderflow.id
  }

  tags = {
    Name = "${var.project_name}-db-cpu-alarm-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_memory" {
  alarm_name          = "${var.project_name}-db-memory-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000000000" # 1GB em bytes
  alarm_description   = "This metric monitors RDS freeable memory"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.orderflow.id
  }

  tags = {
    Name = "${var.project_name}-db-memory-alarm-${var.environment}"
  }
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  alarm_name          = "${var.project_name}-db-storage-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "10000000000" # 10GB em bytes
  alarm_description   = "This metric monitors RDS free storage space"
  alarm_actions       = var.alarm_actions

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.orderflow.id
  }

  tags = {
    Name = "${var.project_name}-db-storage-alarm-${var.environment}"
  }
}

# Read Replica (opcional, apenas para produção)
resource "aws_db_instance" "orderflow_replica" {
  count              = var.create_read_replica ? 1 : 0
  identifier         = "${var.project_name}-db-replica-${var.environment}"
  replicate_source_db = aws_db_instance.orderflow.identifier

  instance_class       = var.db_instance_class
  publicly_accessible  = false
  skip_final_snapshot  = true

  # Monitoring (simplified for AWS Lab)
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  # monitoring_interval removed due to IAM restrictions in AWS Lab
  # monitoring_role_arn removed due to IAM restrictions in AWS Lab
  performance_insights_enabled    = true

  tags = {
    Name = "${var.project_name}-db-replica-${var.environment}"
  }
}
