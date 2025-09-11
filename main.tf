provider "aws" {
  region = "us-west-2"
}

# --- VPC ---
resource "aws_vpc" "vpc1" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "vpc1" }
}

# --- Security Group ---
resource "aws_security_group" "sg1" {
  name        = "sg1"
  description = "In/out traffic on ports 22, 80, 27017"
  vpc_id      = aws_vpc.vpc1.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- IAM Role per EC2 con accesso S3 ---
resource "aws_iam_role" "ec2_s3_role" {
  name = "ec2_s3_access_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "ec2_s3_policy" {
  name   = "ec2_s3_access_policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject","s3:GetObject","s3:ListBucket"]
      Resource = ["arn:aws:s3:::cloning-app-storage","arn:aws:s3:::cloning-app-storage/*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

# --- AMI Amazon Linux 2 ---
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter { name = "name"; values = ["amzn2-ami-hvm-*-x86_64-gp2"] }
}

# --- Volume persistente per MongoDB (EBS) ---
resource "aws_ebs_volume" "mongo_data" {
  availability_zone = "us-west-2a"
  size              = 10
  tags = { Name = "mongo_data_volume" }
}

# --- EC2 Instance ---
resource "aws_instance" "base" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.medium"  # consigliato per DB + app
  vpc_security_group_ids = [aws_security_group.sg1.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3_profile.name

  tags = { Name = "notaboringname_ec2" }

  provisioner "remote-exec" {
    inline = [
      # install Docker e Compose
      "sudo yum update -y",
      "sudo amazon-linux-extras install docker -y",
      "sudo service docker start",
      "sudo usermod -a -G docker ec2-user",
      "sudo curl -L \"https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)\" -o /usr/local/bin/docker-compose",
      "sudo chmod +x /usr/local/bin/docker-compose",
      # mount EBS per MongoDB
      "sudo mkfs -t ext4 /dev/xvdf",
      "sudo mkdir -p /mnt/mongo_data",
      "sudo mount /dev/xvdf /mnt/mongo_data",
      "sudo chown ec2-user:ec2-user /mnt/mongo_data"
    ]
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("chiave.pem")
    host        = self.public_ip
  }
}

# --- Attach EBS volume all'EC2 ---
resource "aws_volume_attachment" "mongo_data_attach" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.mongo_data.id
  instance_id = aws_instance.base.id
}

# --- IAM Instance Profile ---
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "ec2_s3_profile"
  role = aws_iam_role.ec2_s3_role.name
}

# --- S3 bucket ---
resource "aws_s3_bucket" "storage" {
  bucket = "cloning-app-storage"
  acl    = "private"
  tags = { Name = "CloningAppStorage"; Environment = "Dev" }
}

resource "aws_s3_bucket_versioning" "storage_versioning" {
  bucket = aws_s3_bucket.storage.id
  versioning_configuration { status = "Enabled" }
}
