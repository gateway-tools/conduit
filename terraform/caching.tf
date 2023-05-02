resource "random_password" "redis-auth" {
  length           = 52
  special          = false
}

resource "aws_elasticache_parameter_group" "proxy_cache" {
  name   = "proxy-cache"
  family = "redis6.x"
}

resource "aws_elasticache_subnet_group" "proxy_cache" {
  name       = "proxy-cache"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "proxy_cache" {
  automatic_failover_enabled  = true
  multi_az_enabled            = true
  preferred_cache_cluster_azs = var.azs
  replication_group_id        = "proxy-cache"
  description                 = "Redis cache for proxy"
  node_type                   = "cache.t4g.small"
  num_cache_clusters          = length(var.azs)
  parameter_group_name        = aws_elasticache_parameter_group.proxy_cache.name
  port                        = 6379
  at_rest_encryption_enabled  = true
  transit_encryption_enabled  = true
  kms_key_id                  = aws_kms_key.redis.arn
  auth_token                  = random_password.redis-auth.result
  apply_immediately           = true

  subnet_group_name = aws_elasticache_subnet_group.proxy_cache.name

  security_group_ids = [
    aws_security_group.redis.id
  ]
}
