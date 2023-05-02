######
# Domain zones
######

data "aws_route53_zone" "internal_domain" {
  name = var.internal_domain
}

######
# Internal records
######

resource "aws_route53_record" "ipfs_cluster_pinning_api_lb" {
  zone_id = data.aws_route53_zone.internal_domain.zone_id
  name    = "pins.${var.internal_domain}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_lb.ipfs_cluster_pinning_api.dns_name
  ]
}

resource "aws_route53_record" "ipfs_cluster_gateway_certificate" {
  for_each = {
    for dvo in aws_acm_certificate.ipfs_cluster_gateway.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.internal_domain.zone_id
}

resource "aws_route53_record" "ipfs_cluster_pinning_api" {
  for_each = {
    for dvo in aws_acm_certificate.ipfs_cluster_pinning_api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.internal_domain.zone_id
}

resource "aws_route53_record" "app_lb_dns" {
  count   = length(var.app_lb_dns) != 0 ? 1 : 0
  zone_id = data.aws_route53_zone.internal_domain.id
  name    = "*.eth.${var.internal_domain}"
  type    = "CNAME"
  ttl     = "60"
  records = [for record in var.app_lb_dns : record]
}

resource "aws_route53_record" "ipfs_cluster_gateway" {
  zone_id = data.aws_route53_zone.internal_domain.id
  name    = "ipfs.${var.internal_domain}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_lb.ipfs_cluster_gateway.dns_name
  ]
}

######
# Certificates for Internal Domain
######

resource "aws_acm_certificate" "ipfs_cluster_gateway" {
  domain_name       = "ipfs.${var.internal_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "ipfs_cluster_gateway" {
  certificate_arn         = aws_acm_certificate.ipfs_cluster_gateway.arn
  validation_record_fqdns = [for record in aws_route53_record.ipfs_cluster_gateway_certificate : record.fqdn]
}

resource "aws_acm_certificate" "ipfs_cluster_pinning_api" {
  domain_name       = "pins.${var.internal_domain}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "ipfs_cluster_pinning_api" {
  certificate_arn         = aws_acm_certificate.ipfs_cluster_pinning_api.arn
  validation_record_fqdns = [for record in aws_route53_record.ipfs_cluster_pinning_api : record.fqdn]
}
