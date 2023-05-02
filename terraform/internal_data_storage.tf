resource "aws_s3_bucket" "user_data_scripts" {
  bucket = "${var.internal_domain}-userdata"
}

resource "aws_s3_bucket_versioning" "user_data_scripts" {
  bucket = aws_s3_bucket.user_data_scripts.bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "user_data_scripts" {
  bucket = aws_s3_bucket.user_data_scripts.bucket

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_acl" "user_data_scripts" {
  bucket = aws_s3_bucket.user_data_scripts.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "user_data_scripts" {
  bucket = aws_s3_bucket.user_data_scripts.id

  block_public_acls   = true
  block_public_policy = true
}

resource "aws_s3_object" "ipfs_user_data" {
  bucket      = aws_s3_bucket.user_data_scripts.id
  key         = "ipfs/ipfs-user-data.sh"
  source      = "${path.module}/user-data/ipfs-user-data.sh"
  kms_key_id  = aws_kms_key.s3.arn
  source_hash = md5(file("${path.module}/user-data/ipfs-user-data.sh"))
}
