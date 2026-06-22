# DDJ-DataHub AWS Deployment — Plan A: Infrastruktur (Minimal)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine EC2-Instanz in eu-central-1 bereitstellen auf der der komplette DDJ-DataHub Docker-Compose-Stack läuft — inklusive PostgreSQL, Redis, PgBouncer, Directus und Nginx mit TLS via Certbot. Der DNS-Record `datahub.rndtech.de` wird **separat** im Repo `inf-udpm-rndtech-route53-terraform` angelegt (siehe Task 4).

**Architecture:** Alles auf einer EC2 t4g.medium (ARM, Graviton3, günstig). Nginx terminiert TLS direkt via Certbot/Let's Encrypt — kein ALB nötig. PostgreSQL läuft als Docker-Container auf derselben Instanz — kein RDS. Nginx-Cache (10s) + Redis-Cache (60s) fangen Lesezugriffe ab, Directus sieht nur Cache-Misses. Bei Bedarf später auf RDS + zweite EC2 migrierbar.

**Tech Stack:** AWS EC2 t4g.medium, Terraform, Docker Compose, Certbot/Let's Encrypt, eu-central-1

**Geschätzte Kosten:** ~26 USD/Monat (EC2 ~25 USD + S3 + Route53 ~1 USD)

---

## Dateistruktur

```
DDJ-DataHub/
├── terraform/
│   ├── main.tf                    # Provider, Backend
│   ├── variables.tf               # Eingabevariablen
│   ├── ec2.tf                     # EC2, Security Group, IAM, Elastic IP
│   ├── s3.tf                      # S3-Bucket für Backups
│   ├── outputs.tf                 # Outputs: IP, SSH-Befehl, URL
│   └── terraform.tfvars.example   # Beispielwerte
└── .gitignore                     # terraform/*.tfvars und *.tfstate ignorieren

inf-udpm-rndtech-route53-terraform/
└── records.tf                     # ← hier wird der A-Record angelegt (Task 4)
```

---

## Task 1: Terraform-Verzeichnis und Provider anlegen

**Files:**
- Create: `terraform/main.tf`
- Create: `terraform/variables.tf`
- Create: `terraform/terraform.tfvars.example`

- [ ] **Schritt 1: Verzeichnis anlegen**

```bash
mkdir -p /Users/b_ramos/Developer/github/ramos-bjoern/DDJ-DataHub/terraform
```

- [ ] **Schritt 2: `terraform/main.tf` anlegen**

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_caller_identity" "current" {}
```

- [ ] **Schritt 3: `terraform/variables.tf` anlegen**

```hcl
variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_profile" {
  type    = string
  default = "default"
}

variable "project" {
  type    = string
  default = "ddj-datahub"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "domain" {
  description = "Vollständige Domain für Directus (für Certbot und outputs)"
  type        = string
  default     = "datahub.rndtech.de"
}

variable "ec2_instance_type" {
  description = "EC2 Instance Type (t4g = ARM/Graviton, günstig)"
  type        = string
  default     = "t4g.medium"
}

variable "ec2_key_name" {
  description = "Name des EC2 Key Pairs für SSH"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR-Block der SSH-Zugriff erhält (eigene Büro-IP)"
  type        = string
}
```

- [ ] **Schritt 4: `terraform/terraform.tfvars.example` anlegen**

```hcl
aws_region        = "eu-central-1"
aws_profile       = "rndtech-sso"
project           = "ddj-datahub"
environment       = "production"
domain            = "datahub.rndtech.de"
ec2_instance_type = "t4g.medium"
ec2_key_name      = "REPLACE_ME_your_key_pair_name"
allowed_ssh_cidr  = "REPLACE_ME_your_office_ip/32"
```

- [ ] **Schritt 5: `.gitignore` für Terraform ergänzen**

Folgende Zeilen zu `/Users/b_ramos/Developer/github/ramos-bjoern/DDJ-DataHub/.gitignore` hinzufügen:

```
# Terraform
terraform/.terraform/
terraform/*.tfstate
terraform/*.tfstate.backup
terraform/*.tfvars
terraform/.terraform.lock.hcl
```

- [ ] **Schritt 6: Terraform initialisieren**

```bash
cd /Users/b_ramos/Developer/github/ramos-bjoern/DDJ-DataHub/terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars mit echten Werten befüllen
terraform init
```

Erwartete Ausgabe:
```
Terraform has been successfully initialized!
```

- [ ] **Schritt 7: Committen**

```bash
git add terraform/main.tf terraform/variables.tf terraform/terraform.tfvars.example .gitignore
git commit -m "feat(terraform): add provider config and variables for AWS EC2 deployment"
```

---

## Task 2: Security Group

**Files:**
- Create: `terraform/ec2.tf`

- [ ] **Schritt 1: `terraform/ec2.tf` anlegen**

```hcl
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
    description = "HTTP öffentlich"
  }

  # HTTPS — öffentlich
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS öffentlich"
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

  # Beim ersten Start: Docker + Docker Compose + SSM installieren
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
```

- [ ] **Schritt 2: Plan prüfen**

```bash
cd /Users/b_ramos/Developer/github/ramos-bjoern/DDJ-DataHub/terraform
terraform plan -target=aws_security_group.ec2 -target=aws_instance.main -target=aws_eip.main
```

Erwartete Ausgabe: `Plan: 6 to add, 0 to change, 0 to destroy.`

- [ ] **Schritt 3: Committen**

```bash
git add terraform/ec2.tf
git commit -m "feat(terraform): add EC2 t4g.medium with Docker, Certbot, SSM and Elastic IP"
```

---

## Task 3: S3-Bucket für Datenbank-Backups

**Files:**
- Create: `terraform/s3.tf`

- [ ] **Schritt 1: `terraform/s3.tf` anlegen**

```hcl
# S3-Bucket für tägliche PostgreSQL-Backups (pg_dump)
resource "aws_s3_bucket" "backups" {
  bucket = "${var.project}-backups-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.project}-backups"
    Project     = var.project
    Environment = var.environment
  }
}

# Alte Backups automatisch löschen (90 Tage aufbewahren)
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# Öffentlichen Zugriff blockieren
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Policy für EC2 → S3 Backup-Zugriff
resource "aws_iam_policy" "s3_backups" {
  name        = "${var.project}-s3-backups"
  description = "Erlaubt EC2 das Schreiben von Backups in S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      }
    ]
  })
}
```

- [ ] **Schritt 2: Plan prüfen**

```bash
terraform plan -target=aws_s3_bucket.backups
```

Erwartete Ausgabe: `Plan: 4 to add, 0 to change, 0 to destroy.`

- [ ] **Schritt 3: Committen**

```bash
git add terraform/s3.tf
git commit -m "feat(terraform): add S3 bucket for PostgreSQL backups with 90-day lifecycle"
```

---

## Task 4: Route53-Record im separaten Repo anlegen

**⚠️ Dieses Repo verwaltet DNS nicht selbst.** Der A-Record wird im Repo `inf-udpm-rndtech-route53-terraform` angelegt — so wie alle anderen rndtech.de-Records auch.

**Voraussetzung:** `terraform output ec2_public_ip` aus Task 6 (Schritt 2) liegt vor.

**Files:**
- Modify: `../inf-udpm-rndtech-route53-terraform/records.tf`

- [ ] **Schritt 1: Elastic IP notieren**

```bash
cd /Users/b_ramos/Developer/github/ramos-bjoern/DDJ-DataHub/terraform
terraform output ec2_public_ip
# Beispiel: 3.72.145.210
```

- [ ] **Schritt 2: In Route53-Repo wechseln und Branch anlegen**

```bash
cd /Users/b_ramos/Developer/github/ramos-bjoern/inf-udpm-rndtech-route53-terraform
git checkout main && git pull
git checkout -b feat/add-datahub-record
```

- [ ] **Schritt 3: A-Record am Ende von `records.tf` hinzufügen**

```hcl
resource "aws_route53_record" "datahub_a" {
  name    = "datahub.rndtech.de"
  records = ["REPLACE_ME_elastic_ip"]  # aus terraform output ec2_public_ip
  ttl     = 300
  type    = "A"
  zone_id = aws_route53_zone.rndtech_de.zone_id
}
```

- [ ] **Schritt 4: Plan prüfen**

```bash
terraform plan
```

Erwartete Ausgabe: `Plan: 1 to add, 0 to change, 0 to destroy.`

- [ ] **Schritt 5: Committen und PR erstellen (BCPR-Workflow laut README)**

```bash
git add records.tf
git commit -m "feat: add A-record datahub.rndtech.de → EC2 Elastic IP"
git push origin feat/add-datahub-record
# → PR in GitHub/GitLab erstellen und mergen lassen
```

- [ ] **Schritt 6: DNS-Propagierung prüfen (nach Merge)**

```bash
dig datahub.rndtech.de +short
```

Erwartete Ausgabe: Die Elastic IP aus Schritt 1. Kann bis zu 5 Minuten dauern.

---

## Task 5: Outputs

**Files:**
- Create: `terraform/outputs.tf`

- [ ] **Schritt 1: `terraform/outputs.tf` anlegen**

```hcl
output "ec2_public_ip" {
  description = "Öffentliche IP der EC2-Instanz (Elastic IP)"
  value       = aws_eip.main.public_ip
}

output "ec2_instance_id" {
  description = "EC2 Instance ID (für SSM Session Manager)"
  value       = aws_instance.main.id
}

output "s3_backup_bucket" {
  description = "S3-Bucket Name für PostgreSQL-Backups"
  value       = aws_s3_bucket.backups.id
}

output "url" {
  description = "Öffentliche URL der Plattform"
  value       = "https://${var.domain}"
}

output "ssh_command" {
  description = "SSH-Befehl zur EC2-Instanz"
  value       = "ssh -i ~/.ssh/${var.ec2_key_name}.pem ec2-user@${aws_eip.main.public_ip}"
}

output "ssm_command" {
  description = "SSM Session Manager (ohne SSH-Port)"
  value       = "aws ssm start-session --target ${aws_instance.main.id} --profile ${var.aws_profile}"
}

output "certbot_command" {
  description = "TLS-Zertifikat ausstellen (nach Deploy auf EC2 ausführen)"
  value       = "sudo certbot --nginx -d ${var.domain} --non-interactive --agree-tos -m admin@rndtech.de"
}
```

- [ ] **Schritt 2: Committen**

```bash
git add terraform/outputs.tf
git commit -m "feat(terraform): add outputs for EC2, S3, URL and helpful commands"
```

---

## Task 6: Kompletten Stack deployen und verifizieren

- [ ] **Schritt 1: Vollständigen Plan anzeigen**

```bash
cd /Users/b_ramos/Developer/github/ramos-bjoern/DDJ-DataHub/terraform
terraform plan
```

Erwartete Ausgabe: `Plan: ~12 to add, 0 to change, 0 to destroy.`

- [ ] **Schritt 2: Stack deployen**

```bash
terraform apply
```

Eingabe `yes`. Dauert ~2 Minuten.

- [ ] **Schritt 3: Outputs prüfen**

```bash
terraform output
```

Erwartete Ausgabe:
```
ec2_public_ip    = "x.x.x.x"
ec2_instance_id  = "i-xxxxxxxxxxxxx"
s3_backup_bucket = "ddj-datahub-backups-123456789"
url              = "https://datahub.rndtech.de"
ssh_command      = "ssh -i ~/.ssh/YOUR_KEY.pem ec2-user@x.x.x.x"
ssm_command      = "aws ssm start-session --target i-xxxxx --profile rndtech-sso"
certbot_command  = "sudo certbot --nginx -d datahub.rndtech.de ..."
```

- [ ] **Schritt 4: EC2 per SSH verbinden und User Data abwarten**

```bash
# Warten bis User Data fertig ist (~2 Minuten nach Instance-Start)
ssh -i ~/.ssh/YOUR_KEY.pem ec2-user@$(terraform output -raw ec2_public_ip)
```

Auf EC2 prüfen:
```bash
docker --version
docker compose version
which certbot
```

Erwartete Ausgabe: Docker, Docker Compose und Certbot sind installiert.

- [ ] **Schritt 5: DNS-Propagierung prüfen (nach Route53-PR-Merge aus Task 4)**

```bash
dig datahub.rndtech.de +short
```

Erwartete Ausgabe: Die Elastic IP aus `terraform output ec2_public_ip`. Kann bis zu 5 Minuten dauern.

- [ ] **Schritt 6: Kostenschätzung prüfen**

```
EC2 t4g.medium On-Demand:  ~25 USD/Monat
S3 (<1 GB Backups):         ~0.02 USD/Monat
Route53 (1 Record):         ~0.50 USD/Monat
Elastic IP (in use):         0.00 USD/Monat
─────────────────────────────────────────
Gesamt:                    ~26 USD/Monat
```

---

## Self-Review Checkliste

- [ ] EC2 t4g.medium läuft in eu-central-1
- [ ] Security Group: Port 22 nur von Büro-IP, Port 80+443 öffentlich
- [ ] Elastic IP ist zugewiesen — IP bleibt nach Reboot gleich
- [ ] S3-Bucket für Backups existiert, 90-Tage-Lifecycle aktiv
- [ ] Route53 A-Record in `inf-udpm-rndtech-route53-terraform` gemergt
- [ ] `dig datahub.rndtech.de` liefert die korrekte Elastic IP
- [ ] Docker + Docker Compose + Certbot auf EC2 installiert
- [ ] SSM Session Manager funktioniert (kein Port 22 nötig)
- [ ] Keine Secrets in Git (terraform.tfvars in .gitignore)

---

## Nächste Schritte nach Plan A

- **Plan B:** Docker-Compose-Stack auf EC2 deployen + Certbot TLS einrichten
- **Plan C:** GitHub Actions CI/CD Pipeline
- **Später bei Bedarf:** RDS Migration (30 Min. Arbeit, pg_dump + pg_restore)
