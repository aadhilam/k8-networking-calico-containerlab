

# Container Labs Infrastructure - Terraform Configuration
# 
# This Terraform script provisions a complete AWS infrastructure for containerized 
# networking labs and Kubernetes testing. It creates:
#
# 1. VPC (10.0.0.0/16) with DNS support for container networking
# 2. Public subnet (10.0.1.0/24) in the first available AZ
# 3. Internet Gateway and routing for external connectivity
# 4. Security group allowing SSH access (port 22) from anywhere
# 5. EC2 key pair using your local SSH public key (~/.ssh/id_rsa.pub)
# 6. t3.2xlarge EC2 instance (8 vCPUs, 32GB RAM) running Ubuntu 22.04 LTS
# 7. 50GB GP3 SSD storage for container images and lab data
#
# The instance will be configured via Ansible with Docker, ContainerLab, Kind,
# and kubectl for comprehensive container and Kubernetes testing capabilities.
#
# Outputs: Public IP address saved to ec2_ip.txt for easy SSH access

provider "aws" {
  region = "us-east-1"
}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "containerlab-vpc"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "containerlab-igw"
  }
}

# Create public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "containerlab-public-subnet"
  }
}

# Create route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "containerlab-public-rt"
  }
}

# Associate route table with public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Create security group
resource "aws_security_group" "containerlab" {
  name_prefix = "containerlab-"
  description = "Security group for ContainerLab EC2 instance"
  vpc_id      = aws_vpc.main.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "containerlab-sg"
  }
}

resource "aws_key_pair" "key" {
  key_name   = "containerlab-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "clab" {
  ami                    = "ami-0fc5d935ebf8bc3bc" # Ubuntu 22.04 LTS
  instance_type          = "t3.2xlarge"
  key_name               = aws_key_pair.key.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.containerlab.id]

  root_block_device {
    volume_size           = 50    # Size in GB (default is typically 8GB)
    volume_type           = "gp3" # General Purpose SSD
    delete_on_termination = true
  }

  tags = {
    Name = "containerlab-ec2"
  }

  provisioner "local-exec" {
    command = "echo ${self.public_ip} > ec2_ip.txt"
  }
}