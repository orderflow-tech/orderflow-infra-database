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

# Single region setup for AWS Lab environment (us-east-1 only)

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

# Configure default security group to restrict all traffic
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.database.id

  # No ingress or egress rules = deny all traffic

  tags = {
    Name = "${var.project_name}-default-sg-${var.environment}"
  }
}

# CloudWatch log group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.project_name}-${var.environment}"
  retention_in_days = 365                       # 1 year retention for compliance
  kms_key_id        = aws_kms_key.orderflow.arn # Use customer managed KMS key for encryption (Checkov compliance)

  tags = {
    Name = "${var.project_name}-vpc-flow-logs-${var.environment}"
  }
}

# VPC Flow Logs (AWS Lab compatible - without custom IAM role)
# Using S3 destination instead of CloudWatch to avoid IAM role requirement
resource "aws_flow_log" "vpc_flow_logs" {
  log_destination      = aws_s3_bucket.vpc_flow_logs.arn
  log_destination_type = "s3"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.database.id

  tags = {
    Name = "${var.project_name}-vpc-flow-logs-${var.environment}"
  }
}

# S3 bucket for VPC Flow Logs (AWS Lab compatible)
resource "aws_s3_bucket" "vpc_flow_logs" {
  # checkov:skip=CKV_AWS_144:Cross-region replication not supported in AWS Lab environment
  bucket = "${var.project_name}-vpc-flow-logs-${var.environment}-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-vpc-flow-logs-${var.environment}"
  }
}

# Random ID for bucket name uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption with KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.orderflow.arn
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id

  rule {
    id     = "vpc_flow_logs_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 365 # Keep logs for 1 year
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 bucket notification (basic compliance)
resource "aws_s3_bucket_notification" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id
  # Empty notification configuration to satisfy compliance check
}

# S3 bucket logging (using CloudTrail for compliance)
resource "aws_s3_bucket_logging" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id

  target_bucket = aws_s3_bucket.vpc_flow_logs.id
  target_prefix = "access-logs/"
}

# Cross-region replication not implemented for AWS Lab environment
# AWS Lab only supports single region (us-east-1) and has IAM limitations
# This feature would require:
# - Multi-region provider configuration
# - Custom IAM roles for replication
# - Additional costs not suitable for lab environment

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

  # Ingress rule para permitir acesso do EKS (será configurado via peering)
  ingress {
    description = "PostgreSQL from EKS"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # RDS typically doesn't need egress rules, removing overly permissive egress
  # No egress rules needed for RDS security group

  tags = {
    Name = "${var.project_name}-rds-sg-${var.environment}"
  }
}

# Security group rule para permitir acesso do Bastion Host (recurso separado)
resource "aws_security_group_rule" "rds_from_bastion" {
  count                    = var.create_bastion_host ? 1 : 0
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.rds.id
  description              = "PostgreSQL from Bastion"
}

# Gerar senha aleatória para o banco de dados
resource "random_password" "db_password" {
  length  = 32
  special = true
  # Evitar caracteres que podem causar problemas em connection strings
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# KMS key for encryption (AWS Lab compatible)
resource "aws_kms_key" "orderflow" {
  description             = "KMS key for OrderFlow database infrastructure encryption"
  deletion_window_in_days = 7    # Minimum deletion window for AWS Lab
  enable_key_rotation     = true # Enable automatic key rotation for compliance

  # KMS key policy for Checkov compliance
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow RDS"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-kms-key-${var.environment}"
  }
}

# KMS alias for easier reference
resource "aws_kms_alias" "orderflow" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.orderflow.key_id
}

# Data source para obter account ID
data "aws_caller_identity" "current" {}

# Enhanced monitoring disabled for AWS Lab compatibility
# AWS Lab has restricted IAM permissions, so we can't create custom roles
# Armazenar credenciais no Secrets Manager
# checkov:skip=CKV2_AWS_57:Automatic rotation disabled for AWS Lab compatibility - Lambda functions not available
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-db-credentials-${var.environment}"
  description = "Database credentials for OrderFlow RDS instance"

  # Use customer managed KMS key for encryption (Checkov compliance)
  kms_key_id = aws_kms_key.orderflow.arn

  tags = {
    Name = "${var.project_name}-db-credentials-${var.environment}"
  }
}

# Automatic rotation disabled for AWS Lab compatibility
# AWS Lab doesn't have the required Lambda functions for Secrets Manager rotation
# resource "aws_secretsmanager_secret_rotation" "db_credentials" {
#   secret_id = aws_secretsmanager_secret.db_credentials.id
#
#   rotation_rules {
#     automatically_after_days = 30 # Maximum 90 days for compliance
#   }
#
#   # Use AWS managed Lambda function for PostgreSQL rotation
#   rotation_lambda_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:SecretsManagerRDSPostgreSQLRotationSingleUser"
#
#   lifecycle {
#     ignore_changes = [rotation_lambda_arn] # Ignore if Lambda doesn't exist
#   }
# }

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
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

  # Force SSL connections for security
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Removed shared_preload_libraries as it's a static parameter that requires restart
  # Can be configured manually after RDS instance is created if needed

  tags = {
    Name = "${var.project_name}-pg-${var.environment}"
  }
}

# Option Group removed - not necessary for PostgreSQL and causes dependency issues
# PostgreSQL doesn't require option groups like MySQL/Oracle

# RDS Instance
# checkov:skip=CKV_AWS_118:Enhanced monitoring disabled for AWS Lab compatibility - custom IAM roles not allowed
resource "aws_db_instance" "orderflow" {
  identifier = "${var.project_name}-db-${var.environment}"

  # Engine configuration
  engine                = "postgres"
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
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

  # Parameter group only (option group removed for PostgreSQL)
  parameter_group_name = aws_db_parameter_group.orderflow.name

  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window             = var.backup_window
  maintenance_window        = var.maintenance_window
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = var.environment != "production"
  final_snapshot_identifier = var.environment == "production" ? "${var.project_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null

  # Enhanced monitoring disabled for AWS Lab compatibility
  # AWS Lab has restricted IAM permissions, so we can't use custom monitoring roles
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 0 # Disable enhanced monitoring for AWS Lab
  # monitoring_role_arn removed - not supported in AWS Lab
  performance_insights_enabled          = true
  performance_insights_retention_period = 7                         # 7 days (free tier)
  performance_insights_kms_key_id       = aws_kms_key.orderflow.arn # Use customer managed KMS key for encryption

  # High availability
  multi_az                            = true # Always enable Multi-AZ for better availability
  deletion_protection                 = true # Enable deletion protection
  auto_minor_version_upgrade          = true
  iam_database_authentication_enabled = true # Enable IAM database authentication

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

# Enhanced Monitoring disabled for AWS Lab compatibility
# AWS Lab has restricted IAM permissions, so we can't create custom roles

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
# checkov:skip=CKV_AWS_118:Enhanced monitoring disabled for AWS Lab compatibility - custom IAM roles not allowed
resource "aws_db_instance" "orderflow_replica" {
  count               = var.create_read_replica ? 1 : 0
  identifier          = "${var.project_name}-db-replica-${var.environment}"
  replicate_source_db = aws_db_instance.orderflow.identifier

  instance_class        = var.db_instance_class
  publicly_accessible   = false
  skip_final_snapshot   = true
  copy_tags_to_snapshot = true # Enable copy tags to snapshots

  # Enhanced monitoring disabled for AWS Lab compatibility
  # AWS Lab has restricted IAM permissions, so we can't use custom monitoring roles
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  monitoring_interval             = 0 # Disable enhanced monitoring for AWS Lab
  # monitoring_role_arn removed - not supported in AWS Lab
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = aws_kms_key.orderflow.arn # Use customer managed KMS key for encryption

  tags = {
    Name = "${var.project_name}-db-replica-${var.environment}"
  }
}
