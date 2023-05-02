resource "aws_dynamodb_table" "certificates" {
  name             = "certificates"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "PrimaryKey"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.certificates.arn
  }

  attribute {
    name = "PrimaryKey"
    type = "S"
  }
}
