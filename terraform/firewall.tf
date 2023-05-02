resource "aws_security_group" "egress-all" {
  name        = "egress-all"
  description = "Allow all outbound traffic"
  vpc_id      = var.vpc_id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "All all egress traffic"
  }
}

resource "aws_security_group" "redis" {
  name        = "redis"
  description = "Allow Redis traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6380
    protocol    = "tcp"
    self        = true
    description = "All inbound Redis traffic from self"
  }
}

resource "aws_security_group" "conduit" {
  name        = "conduit"
  description = "Allow ENS proxy traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    self        = true
    description = "All inbound ENS proxy traffic"
  }

  ingress {
    from_port   = 9999
    to_port     = 9999
    protocol    = "tcp"
    self        = true
    description = "All inbound ENS proxy traffic for /ask"
  }

  ingress {
    from_port       = 9999
    to_port         = 9999
    protocol        = "tcp"
    security_groups = var.eks_cluster_security_group
    description     = "All inbound EKS cluster traffic for /ask"
  }

  ingress {
    from_port       = 8888
    to_port         = 8888
    protocol        = "tcp"
    security_groups = var.eks_cluster_security_group
    description     = "All inbound EKS cluster traffic"
  }
}

resource "aws_security_group" "caddy" {
  name        = "caddy"
  description = "Allow Caddy traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "All inbound Caddy HTTP traffic"
  }

  ingress {
    from_port        = 8443
    to_port          = 8443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "All inbound Caddy HTTPS traffic"
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = var.eks_cluster_security_group
    description     = "All inbound Caddy HTTP traffic"
  }

  ingress {
    from_port       = 8443
    to_port         = 8443
    protocol        = "tcp"
    security_groups = var.eks_cluster_security_group
    description     = "All inbound Caddy HTTPS traffic"
  }

  tags = {
    Name = "caddy"
  }
}

resource "aws_security_group" "ipfs-swarm" {
  name        = "ipfs-swarm"
  description = "Allow IPFS swarm traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 4001
    to_port          = 4001
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "All inbound IPFS swarm TCP traffic"
  }

  ingress {
    from_port        = 4001
    to_port          = 4001
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "All inbound IPFS swarm UDP traffic"
  }

  tags = {
    Name = "ipfs-swarm"
  }
}

resource "aws_security_group" "ipfs_cluster" {
  name        = "ipfs-cluster"
  description = "Allow IPFS cluster peer traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    self        = true
    description = "All inbound IPFS cluster peer traffic"
  }

  ingress {
    from_port   = 9097
    to_port     = 9097
    protocol    = "tcp"
    self        = true
    description = "Allow IPFS pinning API traffic from LB"
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    self        = true
    description = "All inbound IPFS gateway traffic"
  }
}

resource "aws_security_group" "https_all" {
  name        = "https-all"
  description = "Allow all HTTPS traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
    description      = "Allow all HTTPS traffic"
  }
}

resource "aws_security_group" "ipfs_cluster_pinning_api" {
  name        = "ipfs-cluster-pinning-api-lb"
  description = "Allow IPFS pinning API traffic from LB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 9097
    to_port     = 9097
    protocol    = "tcp"
    self        = true
    description = "Allow IPFS pinning API traffic from LB"
  }
}

resource "aws_security_group" "ipfs_gateway" {
  name        = "ipfs-gateway"
  description = "Allow IPFS gateway traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    self        = true
    description = "All inbound IPFS gateway traffic"
  }
}

resource "aws_security_group" "ipfs_loadbalancer" {
  name        = "ipfs-gateway-lb"
  description = "Allow IPFS gateway LB traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    description = "All inbound IPFS gateway LB traffic"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.vpc.cidr_block]
    description = "All inbound IPFS gateway LB traffic"
  }
}

resource "aws_security_group" "ssh_all" {
  name        = "ssh-all"
  description = "Allow SSH traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
    description = "All inbound SSH traffic"
  }

  tags = {
    Name = "ssh-all"
  }
}
