resource "aws_ebs_volume" "ipfs_cluster_bootstrap" {
  availability_zone = data.aws_availability_zones.all.names.0
  size              = var.ipfs_volume_size
  encrypted         = true
  final_snapshot    = true
  iops              = var.ipfs_volume_iops
  type              = "gp3"
  kms_key_id        = aws_kms_key.ebs.arn

  tags = {
    Name        = "ipfs-cluster-bootstrap",
    ClusterRole = "ipfs-cluster-bootstrap-data"
  }
}

data "aws_ebs_volume" "ipfs_cluster_bootstrap" {
  most_recent = true
  filter {
    name   = "tag:Name"
    values = ["ipfs-cluster-bootstrap"]
  }

  depends_on = [
    aws_ebs_volume.ipfs_cluster_bootstrap
  ]
}

resource "aws_ebs_volume" "ipfs_cluster_peer_0" {
  availability_zone = data.aws_availability_zones.all.names.1
  size              = var.ipfs_volume_size
  encrypted         = true
  final_snapshot    = true
  iops              = var.ipfs_volume_iops
  type              = "gp3"
  kms_key_id        = aws_kms_key.ebs.arn

  tags = {
    Name        = "ipfs-cluster-peer-0"
    ClusterRole = "ipfs-cluster-peer-0-data"
  }
}

data "aws_ebs_volume" "ipfs_cluster_peer_0" {
  most_recent = true
  filter {
    name   = "tag:Name"
    values = ["ipfs-cluster-peer-0"]
  }

  depends_on = [
    aws_ebs_volume.ipfs_cluster_peer_0
  ]
}

resource "aws_ebs_volume" "ipfs_cluster_peer_1" {
  availability_zone = data.aws_availability_zones.all.names.2
  size              = var.ipfs_volume_size
  encrypted         = true
  final_snapshot    = true
  iops              = var.ipfs_volume_iops
  type              = "gp3"
  kms_key_id        = aws_kms_key.ebs.arn

  tags = {
    Name        = "ipfs-cluster-peer-1"
    ClusterRole = "ipfs-cluster-peer-1-data"
  }
}

data "aws_ebs_volume" "ipfs_cluster_peer_1" {
  most_recent = true
  filter {
    name   = "tag:Name"
    values = ["ipfs-cluster-peer-1"]
  }

  depends_on = [
    aws_ebs_volume.ipfs_cluster_peer_1
  ]
}

data "template_file" "ipfs_user_data" {
  template = file("${path.module}/user-data/init-user-data.sh")
  vars = {
    bucket   = aws_s3_bucket.user_data_scripts.id
    region   = data.aws_region.current.name
    path     = "ipfs"
    filename = "ipfs-user-data.sh"
  }
}

resource "tls_private_key" "ipfs_key" {
  algorithm = "RSA"
}

module "ipfs_key" {
  source     = "terraform-aws-modules/key-pair/aws"
  version    = ">=2.0.0"
  key_name   = "ipfs"
  public_key = tls_private_key.ipfs_key.public_key_openssh
}

resource "aws_ssm_parameter" "ipfs-key" {
  name        = module.ipfs_key.key_pair_name
  description = "ipfs nodes key"
  type        = "SecureString"
  value       = tls_private_key.ipfs_key.private_key_pem
}


resource "aws_launch_configuration" "ipfs_cluster" {
  name_prefix          = "ipfs-cluster"
  image_id             = data.aws_ami.amazon_linux.id
  instance_type        = var.ipfs_instance_type
  iam_instance_profile = aws_iam_instance_profile.ipfs_cluster.id
  user_data_base64     = base64encode(data.template_file.ipfs_user_data.rendered)
  key_name             = module.ipfs_key.key_pair_name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  security_groups = [
    aws_security_group.egress-all.id,
    aws_security_group.ipfs_cluster.id,
    aws_security_group.ipfs-swarm.id,
    aws_security_group.egress-all.id,
    aws_security_group.ssh_all.id
  ]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 10
    delete_on_termination = true
    encrypted             = true
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_ebs_volume.ipfs_cluster_bootstrap,
    aws_ebs_volume.ipfs_cluster_peer_0,
    aws_ebs_volume.ipfs_cluster_peer_1,
    aws_s3_object.ipfs_user_data
  ]
}

resource "aws_autoscaling_group" "ipfs_cluster_bootstrap" {
  vpc_zone_identifier  = [for id in lookup(local.availability_zone_subnets, data.aws_ebs_volume.ipfs_cluster_bootstrap.availability_zone, "") : id]
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  launch_configuration = aws_launch_configuration.ipfs_cluster.id
  target_group_arns = [
    aws_lb_target_group.ipfs_cluster_gateway.arn,
    aws_lb_target_group.ipfs_cluster_pinning_api.arn
  ]

  tag {
    key                 = "Name"
    value               = "ipfs-cluster-bootstrap"
    propagate_at_launch = true
    }

  tag {
    key                 = "ClusterRole"
    value               = "ipfs-cluster-bootstrap"
    propagate_at_launch = true
    }

  depends_on = [
    aws_ebs_volume.ipfs_cluster_bootstrap,
    aws_ssm_parameter.ipfs_cluster_id,
    aws_ssm_parameter.ipfs_cluster_private_key,
    aws_ssm_parameter.ipfs_cluster_secret,
    aws_ssm_parameter.ipfs_root_redirect
  ]
}

resource "aws_autoscaling_group" "ipfs_cluster_peer_0" {
  vpc_zone_identifier  = [for id in lookup(local.availability_zone_subnets, data.aws_ebs_volume.ipfs_cluster_peer_0.availability_zone, "") : id]
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  launch_configuration = aws_launch_configuration.ipfs_cluster.id
  target_group_arns = [
    aws_lb_target_group.ipfs_cluster_gateway.arn,
    aws_lb_target_group.ipfs_cluster_pinning_api.arn
  ]

  tag {
    key                 = "Name"
    value               = "ipfs-cluster-peer-0"
    propagate_at_launch = true
  }

  tag  {
    key                 = "ClusterRole"
    value               = "ipfs-cluster-peer-0"
    propagate_at_launch = true
    }

  depends_on = [
    aws_autoscaling_group.ipfs_cluster_bootstrap,
    aws_ebs_volume.ipfs_cluster_peer_0,
    aws_ssm_parameter.ipfs_cluster_id,
    aws_ssm_parameter.ipfs_cluster_private_key,
    aws_ssm_parameter.ipfs_cluster_secret,
    aws_ssm_parameter.ipfs_root_redirect
  ]
}

resource "aws_autoscaling_group" "ipfs_cluster_peer_1" {
  vpc_zone_identifier  = [for id in lookup(local.availability_zone_subnets, data.aws_ebs_volume.ipfs_cluster_peer_1.availability_zone, "") : id]
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  launch_configuration = aws_launch_configuration.ipfs_cluster.id
  target_group_arns = [
    aws_lb_target_group.ipfs_cluster_gateway.arn,
    aws_lb_target_group.ipfs_cluster_pinning_api.arn
  ]

  tag {
    key                 = "Name"
    value               = "ipfs-cluster-peer-1"
    propagate_at_launch = true
    }

  tag {
    key                 = "ClusterRole"
    value               = "ipfs-cluster-peer-1"
    propagate_at_launch = true
    }

  depends_on = [
    aws_autoscaling_group.ipfs_cluster_peer_0,
    aws_ebs_volume.ipfs_cluster_peer_1,
    aws_ssm_parameter.ipfs_cluster_id,
    aws_ssm_parameter.ipfs_cluster_private_key,
    aws_ssm_parameter.ipfs_cluster_secret,
    aws_ssm_parameter.ipfs_root_redirect
  ]
}
