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

  # SSH access from anywhere (você pode restringir para seu IP)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Considere restringir para seu IP específico
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg-${var.environment}"
  }
}

# Subnet pública para o bastion host
resource "aws_subnet" "bastion_public" {
  vpc_id                  = aws_vpc.database.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 10) # Usa um bloco diferente
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

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

# Bastion Host EC2 Instance
resource "aws_instance" "bastion" {
  count                  = var.create_bastion_host && var.bastion_public_key != "" ? 1 : 0
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.nano" # Instância muito pequena e barata
  key_name               = var.create_bastion_host && var.bastion_public_key != "" ? aws_key_pair.bastion[0].key_name : null
  vpc_security_group_ids = [aws_security_group.bastion.id]
  subnet_id              = aws_subnet.bastion_public.id

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