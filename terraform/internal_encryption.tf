resource "aws_kms_key" "k8s_secrets" {
  description             = "KMS key for Kubernetes secrets"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "k8s_secrets" {
  name          = "alias/k8s-secrets"
  target_key_id = aws_kms_key.k8s_secrets.key_id
}

resource "aws_kms_key" "parameter_store" {
  description             = "KMS key for AWS SSM Parameter Store values"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "parameter_store" {
  name          = "alias/parameter-store"
  target_key_id = aws_kms_key.parameter_store.key_id
}

resource "aws_kms_key" "certificates" {
  description             = "KMS key for Let's Encrypt certificate storage"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "certificates" {
  name          = "alias/certificates"
  target_key_id = aws_kms_key.certificates.key_id
}

resource "aws_kms_key" "redis" {
  description             = "KMS key for Redis Elasticache"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "redis" {
  name          = "alias/redis"
  target_key_id = aws_kms_key.redis.key_id
}

resource "aws_kms_key" "ebs" {
  description             = "KMS key for EBS volumes"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/ebs"
  target_key_id = aws_kms_key.ebs.key_id
}

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 buckets"
  deletion_window_in_days = 10
}

resource "aws_kms_alias" "s3" {
  name          = "alias/s3"
  target_key_id = aws_kms_key.s3.key_id
}
