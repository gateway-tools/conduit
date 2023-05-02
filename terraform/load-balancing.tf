resource "aws_lb" "ipfs_cluster_gateway" {
  name               = "ipfs-gateway"
  internal           = true
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.egress-all.id,
    aws_security_group.ipfs_loadbalancer.id,
    aws_security_group.ipfs_cluster.id
  ]
  subnets = [for subnet in var.private_subnet_ids : subnet]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "ipfs_cluster_gateway" {
  name     = "ipfs-cluster-gateway"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    interval            = 5
    path                = "/"
    timeout             = 2
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-404"
  }
}

resource "aws_lb_listener" "ipfs_cluster_gateway_https" {
  load_balancer_arn = aws_lb.ipfs_cluster_gateway.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
  certificate_arn   = aws_acm_certificate.ipfs_cluster_gateway.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ipfs_cluster_gateway.arn
  }

  depends_on = [
    aws_acm_certificate_validation.ipfs_cluster_gateway
  ]
}

resource "aws_lb_listener" "ipfs_cluster_gateway_http" {
  load_balancer_arn = aws_lb.ipfs_cluster_gateway.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

###
## IPFS Pinning API
###

resource "aws_lb" "ipfs_cluster_pinning_api" {
  name               = "ipfs-cluster-pinning-api"
  ip_address_type    = "dualstack"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_security_group.egress-all.id,
    aws_security_group.ipfs_cluster.id,
    aws_security_group.https_all.id
  ]
  subnets = [for subnet in var.public_subnet_ids : subnet]

  enable_deletion_protection = false
}

resource "aws_lb_target_group" "ipfs_cluster_pinning_api" {
  name     = "ipfs-cluster-pinning-api"
  port     = 9097
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    interval            = 5
    path                = "/"
    timeout             = 2
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200-404"
  }
}

resource "aws_lb_listener" "ipfs_cluster_pinning_api" {
  load_balancer_arn = aws_lb.ipfs_cluster_pinning_api.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-FS-1-2-Res-2020-10"
  certificate_arn   = aws_acm_certificate.ipfs_cluster_pinning_api.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Unauthorized"
      status_code  = "403"
    }
  }

  depends_on = [
    aws_acm_certificate_validation.ipfs_cluster_pinning_api
  ]
}

resource "aws_lb_listener_rule" "ipfs_cluster_pinning_api" {
  listener_arn = aws_lb_listener.ipfs_cluster_pinning_api.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ipfs_cluster_pinning_api.arn
  }

  condition {
    path_pattern {
      values = ["/pins/*"]
    }
  }

  condition {
    http_request_method {
      values = ["GET", "POST"]
    }
  }

}

