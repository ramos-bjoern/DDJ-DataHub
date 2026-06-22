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

output "route53_instruction" {
  description = "Anweisung für Route53-Record im separaten Repo"
  value       = "In inf-udpm-rndtech-route53-terraform/records.tf hinzufügen: resource \"aws_route53_record\" \"datahub_a\" { name = \"datahub.rndtech.de\" records = [\"${aws_eip.main.public_ip}\"] ttl = 300 type = \"A\" zone_id = aws_route53_zone.rndtech_de.zone_id }"
}
