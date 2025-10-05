# Bastion Host para acesso seguro ao banco de dados
# Este recurso cria uma instância EC2 pequena para servir como "ponte" para o RDS

# Key Pair para acesso SSH ao bastion (apenas se bastion estiver habilitado)
resource "aws_key_pair" "bastion" {
  count      = var.create_bastion_host && var.bastion_public_key != "" ? 1 : 0
  key_name   = "${var.project_name}-bastion-key-${var.environment}"
  public_key = var.bastion_public_key
}

# Security Group para o Bastion Host
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg-${var.environment}"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.database.id

  # SSH access from specific IP ranges (more secure)
  ingress {
    description = "SSH access from specific IP ranges"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr_blocks # Use variable for allowed IPs
  }

  # More restrictive egress rules
  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg-${var.environment}"
  }
}

# Security group rule para PostgreSQL do bastion para RDS (recurso separado)
resource "aws_security_group_rule" "bastion_to_rds" {
  count                    = var.create_bastion_host ? 1 : 0
  type                     = "egress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  security_group_id        = aws_security_group.bastion.id
  description              = "PostgreSQL to RDS"
}

# Subnet pública para o bastion host
resource "aws_subnet" "bastion_public" {
  vpc_id                  = aws_vpc.database.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 10) # Usa um bloco diferente
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false # Don't auto-assign public IP

  tags = {
    Name = "${var.project_name}-bastion-subnet-${var.environment}"
    Type = "public"
  }
}

# Route table association para subnet pública do bastion
resource "aws_route_table_association" "bastion_public" {
  subnet_id      = aws_subnet.bastion_public.id
  route_table_id = aws_route_table.database.id
}

# IAM role for bastion host - DISABLED for AWS Lab
# AWS Lab has restricted IAM permissions

# Instance profile removed for AWS Lab compatibility

# Bastion Host EC2 Instance
resource "aws_instance" "bastion" {
  count                  = var.create_bastion_host && var.bastion_public_key != "" ? 1 : 0
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.nano" # Instância muito pequena e barata
  key_name               = var.create_bastion_host && var.bastion_public_key != "" ? aws_key_pair.bastion[0].key_name : null
  vpc_security_group_ids = [aws_security_group.bastion.id]
  subnet_id              = aws_subnet.bastion_public.id

  # Security configurations
  monitoring                  = true  # Enable detailed monitoring
  ebs_optimized               = true  # Enable EBS optimization
  associate_public_ip_address = false # Don't auto-assign public IP

  # IMDSv2 (Instance Metadata Service Version 2)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Require IMDSv2
    http_put_response_hop_limit = 1
  }

  # EBS encryption
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y postgresql15
    
    # Instalar PostgreSQL client
    echo "PostgreSQL client installed successfully" > /tmp/bastion-setup.log
    
    # Criar script de conexão
    cat > /home/ec2-user/connect-db.sh << 'SCRIPT'
#!/bin/bash
echo "Connecting to OrderFlow Database..."
echo "Host: ${aws_db_instance.orderflow.address}"
echo "Port: ${aws_db_instance.orderflow.port}"
echo "Database: ${var.db_name}"
echo "Username: ${var.db_username}"
echo ""
psql -h ${aws_db_instance.orderflow.address} -p ${aws_db_instance.orderflow.port} -U ${var.db_username} -d ${var.db_name}
SCRIPT
    
    chmod +x /home/ec2-user/connect-db.sh
    chown ec2-user:ec2-user /home/ec2-user/connect-db.sh
  EOF
  )

  tags = {
    Name = "${var.project_name}-bastion-${var.environment}"
  }
}

# Data source para obter AMI mais recente do Amazon Linux
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}