terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Fetch latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

# Automatically create an RSA 2048 SSH key pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "generated_key" {
  key_name   = "devops-multi-env-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Save private key locally for Ansible & Jenkins
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/../ansible/devops-key.pem"
  file_permission = "0400"
}

# Security Group: Port 22 from my_ip, Port 80 from anywhere
resource "aws_security_group" "web_sg" {
  name        = "multi-env-web-sg"
  description = "Allow SSH from my IP and HTTP from anywhere"

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "multi-env-web-sg"
  }
}

# Create DEV and PROD EC2 instances using for_each
resource "aws_instance" "servers" {
  for_each               = var.environments
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.web_sg.id]

  root_block_device {
    volume_size = 10
    volume_type = "gp2"
  }

  tags = {
    Name        = "${each.key}-server"
    Environment = each.key
  }
}

# Generate Ansible inventory.ini automatically
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tmpl", {
    dev_ip  = aws_instance.servers["dev"].public_ip
    prod_ip = aws_instance.servers["prod"].public_ip
  })
  filename = "${path.module}/../ansible/inventory.ini"
}