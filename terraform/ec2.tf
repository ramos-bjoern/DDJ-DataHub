# Security Group für EC2
resource "aws_security_group" "ec2" {
  name        = "${var.project}-ec2"
  description = "DDJ-DataHub EC2 Security Group"
  vpc_id      = data.aws_vpc.default.id

  # SSH — nur vom erlaubten CIDR (Büro-IP)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH"
  }

  # HTTP — öffentlich (für Certbot ACME Challenge + Redirect zu HTTPS)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP public"
  }

  # HTTPS — oeffentlich
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS public"
  }

  # Alles raus (Docker-Image-Pulls, Let's Encrypt, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-ec2"
    Project     = var.project
    Environment = var.environment
  }
}

# IAM Role für EC2 (SSM Session Manager — SSH-Alternative)
resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ses" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSESFullAccess"
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.s3_backups.arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# Aktuelles ARM-AMI (Amazon Linux 2023, Graviton)
data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2-Instanz
resource "aws_instance" "main" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.ec2_instance_type
  key_name               = var.ec2_key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id              = tolist(data.aws_subnets.default.ids)[0]

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  # Beim ersten Start: Docker + Docker Compose + Certbot + SSM installieren
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    dnf update -y
    dnf install -y docker git

    systemctl enable --now docker
    usermod -aG docker ec2-user

    # Docker Compose Plugin (ARM-Version)
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64" \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # Certbot für Let's Encrypt TLS
    dnf install -y python3-pip
    pip3 install certbot certbot-nginx

    # SSM Agent
    dnf install -y amazon-ssm-agent
    systemctl enable --now amazon-ssm-agent

    # Arbeitsverzeichnis
    mkdir -p /opt/ddj-datahub
    chown ec2-user:ec2-user /opt/ddj-datahub
  EOF
  )

  tags = {
    Name        = "${var.project}-server"
    Project     = var.project
    Environment = var.environment
  }
}

# Elastic IP — bleibt gleich nach Reboot/Rebuild
resource "aws_eip" "main" {
  instance = aws_instance.main.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project}-eip"
    Project     = var.project
    Environment = var.environment
  }
}
