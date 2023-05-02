resource "aws_ssm_parameter" "ipfs_cluster_id" {
  name      = "/ipfs/cluster/id"
  type      = "SecureString"
  value     = var.ipfs_cluster_key_id
  overwrite = true
  key_id    = aws_kms_key.parameter_store.key_id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "ipfs_cluster_private_key" {
  name      = "/ipfs/cluster/private_key"
  type      = "SecureString"
  value     = var.ipfs_cluster_key
  overwrite = true
  key_id    = aws_kms_key.parameter_store.key_id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "ipfs_cluster_secret" {
  name      = "/ipfs/cluster/secret"
  type      = "SecureString"
  value     = var.ipfs_cluster_secret
  overwrite = true
  key_id    = aws_kms_key.parameter_store.key_id

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "ipfs_root_redirect" {
  name = "/ipfs/cluster/root_redirect"
  type = "SecureString"
  value = "https://${var.public_domain}"
  overwrite = true
  key_id    = aws_kms_key.parameter_store.key_id
}
