######
# Local data
######

locals {
  tags = {
    "environment" = "Production"
    "Terraform" = "true"
  }

  eks_oidc_id = replace(join("", aws_eks_cluster.eks_cluster.*.identity.0.oidc.0.issuer), "https://oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/", "")

  availability_zone_subnets = {
    for s in data.aws_subnet.pub_subnets : s.availability_zone => s.id...
  }
}

######
# Data Sources for infrastructure
######

data "aws_availability_zones" "all" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.eks_cluster.identity.0.oidc.0.issuer
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

data "aws_subnet" "pub_subnets" {
  for_each = toset(var.public_subnet_ids)
  id = each.key
}

data "aws_subnet" "priv_subnets" {
  for_each = toset(var.private_subnet_ids)
  id = each.key
}
