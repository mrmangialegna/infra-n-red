# networking.tf

# -------------------------
# VPC
# -------------------------
resource "aws_vpc" "paas_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "paas-vpc"
  }
}

# -------------------------
# Public Subnet (for ALB)
# -------------------------
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.paas_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "paas-public-subnet-1"
  }
}

# -------------------------
# Private Subnets (for K8s nodes / pods)
# -------------------------
resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.paas_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "paas-private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.paas_vpc.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "paas-private-subnet-2"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.paas_vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "paas-public-subnet-2"
  }
}

resource "aws_subnet" "public_subnet_3" {
  vpc_id                  = aws_vpc.paas_vpc.id
  cidr_block              = "10.0.5.0/24"
  availability_zone       = "${var.aws_region}c"
  map_public_ip_on_launch = true

  tags = {
    Name = "paas-public-subnet-3"
  }
}

resource "aws_subnet" "private_subnet_3" {
  vpc_id            = aws_vpc.paas_vpc.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "${var.aws_region}c"

  tags = {
    Name = "paas-private-subnet-3"
  }
}

# -------------------------
# Internet Gateway
# -------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.paas_vpc.id

  tags = {
    Name = "paas-igw"
  }
}

# -------------------------
# Route Table for Public Subnet
# -------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.paas_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "paas-public-rt"
  }
}

resource "aws_route_table_association" "public_rta" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rta_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rta_3" {
  subnet_id      = aws_subnet.public_subnet_3.id
  route_table_id = aws_route_table.public_rt.id
}

# -------------------------
# Private Route Table (for VPC Endpoints)
# -------------------------
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.paas_vpc.id

  tags = {
    Name = "paas-private-rt"
  }
}

resource "aws_route_table_association" "private_rta_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_rta_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "private_rta_3" {
  subnet_id      = aws_subnet.private_subnet_3.id
  route_table_id = aws_route_table.private_rt.id
}

# -------------------------
# Network ACLs for additional security
# -------------------------
resource "aws_network_acl" "private_nacl" {
  vpc_id     = aws_vpc.paas_vpc.id
  subnet_ids = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id,
    aws_subnet.private_subnet_3.id
  ]

  # Allow internal VPC traffic
  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.paas_vpc.cidr_block
  }

  # Allow return traffic
  ingress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
  }

  tags = {
    Name = "paas-private-nacl"
  }
}

# -------------------------
# Security Group for ALB
# -------------------------
resource "aws_security_group" "alb_sg" {
  name        = "paas-alb-sg"
  description = "Allow HTTP/HTTPS to ALB"
  vpc_id      = aws_vpc.paas_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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
    Name = "paas-alb-sg"
  }
}

# -------------------------
# Security Group for K8s nodes
# -------------------------
resource "aws_security_group" "k8s_sg" {
  name        = "paas-k8s-sg"
  description = "Allow traffic from ALB and internal cluster"
  vpc_id      = aws_vpc.paas_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.paas_vpc.cidr_block]
  }

  # Allow all traffic from ALB
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Allow internal cluster communication
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.paas_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "paas-k8s-sg"
  }
}

# -------------------------
# Security Group for VPC Endpoints
# -------------------------
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "paas-vpc-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.paas_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.paas_vpc.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "paas-vpc-endpoint-sg"
  }
}
