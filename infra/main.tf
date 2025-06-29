terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

###########################
# 1. Networking layer    #
###########################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cohere-poc-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "cohere-poc-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

###########################
# 2. Security group       #
###########################

resource "aws_security_group" "bastion" {
  name        = "cohere-bastion-sg"
  description = "Bastion & tasks - allow 8080 within SG; outbound everywhere"
  vpc_id      = aws_vpc.main.id

  # Allow tasks and bastion (same SG) to talk to each other on 8080
  ingress {
    description      = "App HTTP"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    self             = true  # same‑SG traffic only
  }

  # Outbound to Internet / SSM endpoints
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###########################
# 3. SSM instance profile #
###########################

resource "aws_iam_role" "ssm" {
  name = "SSM_Bastion_Role_POC"  # renamed to avoid collision

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Action    = "sts:AssumeRole",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "SSM_Bastion_Profile_POC"  # renamed to align with role
  role = aws_iam_role.ssm.name
}

###########################
# 4. Bastion host        #
###########################

resource "aws_instance" "bastion" {
  ami                         = "ami-053b0d53c279acc90" # Amazon Linux 2
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm.name
  associate_public_ip_address = true

  tags = {
    Name = "cohere-poc-bastion"
  }
}

###########################
# 5. ECS skeleton         #
###########################

resource "aws_ecs_cluster" "poc" {
  name = "cohere-poc-cluster"
}

###########################
# 6. Helpful outputs      #
###########################

output "vpc_id"             { value = aws_vpc.main.id }
output "public_subnet_id"   { value = aws_subnet.public.id }
output "bastion_sg_id"      { value = aws_security_group.bastion.id }
output "bastion_id"         { value = aws_instance.bastion.id }
output "ecs_cluster_name"   { value = aws_ecs_cluster.poc.name }
