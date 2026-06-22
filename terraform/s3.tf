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

    filter {}

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
