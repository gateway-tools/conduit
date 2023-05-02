resource "aws_eks_cluster" "eks_cluster" {
  name                      = var.cluster_name
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  role_arn                  = aws_iam_role.eks_cluster.arn
  version                   = "1.22"

  vpc_config {
    subnet_ids = concat(var.private_subnet_ids, var.public_subnet_ids)
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.k8s_secrets.arn
    }

    resources = [
      "secrets"
    ]
  }

  tags = {
    Name = var.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.AmazonEKSServicePolicy
  ]
}

resource "aws_eks_node_group" "node" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "nodegroup-${aws_eks_cluster.eks_cluster.name}"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = concat(var.private_subnet_ids, var.public_subnet_ids)
  instance_types  = ["t3.small"]
  disk_size       = 5

  labels = {
    service = "coredns"
  }

  scaling_config {
    desired_size = var.desired_nodes
    max_size     = var.max_nodes
    min_size     = var.min_nodes
  }
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_eks_node_group" "controllers" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "nodegroup-${aws_eks_cluster.eks_cluster.name}-controllers"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["t3.medium"]
  disk_size       = 5

  labels = {
    service = "controllers"
  }

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }

  tags = {
    "k8s.io/cluster-autoscaler/${aws_eks_cluster.eks_cluster.name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"                             = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}
