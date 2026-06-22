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
