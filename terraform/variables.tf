variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be dev, staging, or production."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "orderflow"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "database_subnet_count" {
  description = "Number of subnets to create for the database"
  type        = number
  default     = 2

  validation {
    condition     = var.database_subnet_count >= 2
    error_message = "At least 2 subnets are required for RDS Multi-AZ."
  }
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the database"
  type        = list(string)
  default     = ["10.0.0.0/16"] # CIDR do EKS VPC
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "orderflowdb"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "orderflow_admin"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.10"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.", var.db_instance_class))
    error_message = "Instance class must start with 'db.'."
  }
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20
    error_message = "Allocated storage must be at least 20 GB."
  }
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.db_max_allocated_storage >= 20
    error_message = "Max allocated storage must be at least 20 GB."
  }
}

variable "db_iops" {
  description = "Provisioned IOPS for the database (only for io1/io2 storage type)"
  type        = number
  default     = 3000
}

variable "publicly_accessible" {
  description = "Whether the database should be publicly accessible"
  type        = bool
  default     = false # Secure: no public access
}

variable "backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

variable "backup_window" {
  description = "Preferred backup window (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window (UTC)"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "multi_az" {
  description = "Whether to enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "create_read_replica" {
  description = "Whether to create a read replica"
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger (e.g., SNS topics)"
  type        = list(string)
  default     = []
}

variable "create_bastion_host" {
  description = "Whether to create a bastion host for database access"
  type        = bool
  default     = false # Set to true if you want bastion host
}

variable "bastion_public_key" {
  description = "Public key for SSH access to bastion host"
  type        = string
  default     = "" # You'll need to provide your SSH public key
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access to bastion host"
  type        = list(string)
  default     = ["10.0.0.0/16"] # More restrictive than 0.0.0.0/0, change to your IP range

  validation {
    condition     = length(var.allowed_ssh_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified for SSH access."
  }
}
