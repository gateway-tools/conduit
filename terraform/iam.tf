data "aws_iam_policy_document" "fargate_logs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_eks_fargate_profile" "main" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = "main"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "default"
  }

}

resource "aws_eks_fargate_profile" "conduit" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = "conduit"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "ens"
    labels = {
      app = "conduit"
    }
  }
}

resource "aws_eks_fargate_profile" "caddy" {
  cluster_name           = aws_eks_cluster.eks_cluster.name
  fargate_profile_name   = "caddy"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution_role.arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "ens"
    labels = {
      app = "caddy"
    }
  }
}

###
## IAM Roles and policies for EKS cluster(s)
###

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:AssumeRoleWithWebIdentity"
      ]
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_cluster.name
}

###
## IAM policies and roles for managed node groups
###

resource "aws_iam_role" "eks_nodes" {
  name = "eks-node-group"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:AssumeRoleWithWebIdentity"
        ]
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

###
## IAM roles and policies for Fargate
###

resource "aws_iam_role" "fargate_pod_execution_role" {
  name                  = "eks-fargate-pod-execution-role"
  force_detach_policies = true

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks-fargate-pods.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole",
        "sts:AssumeRoleWithWebIdentity"
        ]
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution_role.name
}

# Fargate logging

resource "aws_iam_policy" "fargate_logs" {
  name        = "fargate-logs-policy"
  path        = "/eks/"
  description = "Fargate logs policy"

  policy = data.aws_iam_policy_document.fargate_logs.json
}

resource "aws_iam_policy_attachment" "fargate_logs" {
  name       = "fargate-logs-policy"
  roles      = [aws_iam_role.fargate_pod_execution_role.id]
  policy_arn = aws_iam_policy.fargate_logs.arn
}

###
## Caddy server IAM permissions
###

resource "aws_iam_user" "caddy" {
  name = "caddy"
  path = "/certificates/"
}

resource "aws_iam_access_key" "caddy" {
  user = aws_iam_user.caddy.name
}

resource "aws_iam_group" "certificate_users" {
  name = "certificates"
  path = "/certificates/"
}

resource "aws_iam_group_membership" "certificate_users" {
  name = "certificate-users"

  users = [
    aws_iam_user.caddy.name
  ]

  group = aws_iam_group.certificate_users.name
}

resource "aws_iam_group_policy_attachment" "certificates" {
  group      = aws_iam_group.certificate_users.name
  policy_arn = aws_iam_policy.certificates.arn
}

resource "aws_iam_policy" "certificates" {
  name        = "certificate-management"
  path        = "/certificates/"
  description = "Let's Encrypt certificate challenge and storage"

  policy = data.aws_iam_policy_document.certificates.json
}

resource "aws_iam_group_policy_attachment" "prod_certificates" {
  count      = 1
  group      = aws_iam_group.certificate_users.name
  policy_arn = aws_iam_policy.prod_certificates[0].arn
}

resource "aws_iam_policy" "prod_certificates" {
  count       = 1
  name        = "prod-certificate-management"
  path        = "/certificates/"
  description = "Let's Encrypt certificate challenge for production"

  policy = data.aws_iam_policy_document.prod_certificates[0].json
}

data "aws_iam_policy_document" "certificates" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:BatchGet*",
      "dynamodb:DescribeTable",
      "dynamodb:Get*",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWrite*",
      "dynamodb:DeleteItem",
      "dynamodb:UpdateItem",
      "dynamodb:PutItem"
    ]

    resources = [
      aws_dynamodb_table.certificates.arn
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:List*",
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]

    resources = [
      aws_kms_key.certificates.arn
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ListResourceRecordSets",
      "route53:GetChange",
      "route53:ChangeResourceRecordSets"
    ]

    resources = [
      "arn:aws:route53:::hostedzone/${data.aws_route53_zone.internal_domain.id}"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:GetChange"
    ]

    resources = [
      "*"
    ]
  }
}

data "aws_iam_policy_document" "prod_certificates" {
  count = 1

  statement {
    effect = "Allow"

    actions = [
      "route53:ListResourceRecordSets",
      "route53:GetChange",
      "route53:ChangeResourceRecordSets"
    ]

    resources = [
      "arn:aws:route53:::hostedzone/${data.aws_route53_zone.internal_domain.id}"
    ]
  }
}

###
## EKS service account policies
###

# external-dns controller
data "aws_iam_policy_document" "external_dns" {
  statement {
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets"
    ]

    resources = [
      "arn:aws:route53:::hostedzone/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "external-dns"
  path        = "/eks/"
  description = "EKS external-dns policy"

  policy = data.aws_iam_policy_document.external_dns.json
}

resource "aws_iam_policy_attachment" "external_dns" {
  name  = "external_dns"
  roles = [aws_iam_role.external_dns.name]

  policy_arn = aws_iam_policy.external_dns.arn
}

resource "aws_iam_role" "external_dns" {
  name               = "external-dns"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume.json
}

data "aws_iam_policy_document" "external_dns_assume" {
  statement {

    effect = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}"
      ]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}:sub"

      values = [
        "system:serviceaccount:kube-system:external-dns"
      ]
    }
  }
}

# Cluster autoscaler
data "aws_iam_policy_document" "autoscaler" {
  statement {
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"

      values = [
        "owned"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeAutoScalingGroups",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
      "autoscaling:DescribeTags",
      "autoscaling:DescribeLaunchConfigurations"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "autoscaler" {
  name        = "autoscaler"
  path        = "/eks/"
  description = "EKS autoscaler policy"

  policy = data.aws_iam_policy_document.autoscaler.json
}

resource "aws_iam_policy_attachment" "autoscaler" {
  name  = "autoscaler"
  roles = [aws_iam_role.autoscaler.name]

  policy_arn = aws_iam_policy.autoscaler.arn
}

resource "aws_iam_role" "autoscaler" {
  name               = "autoscaler"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.autoscaler_assume.json
}

data "aws_iam_policy_document" "autoscaler_assume" {
  statement {

    effect = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}"
      ]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}:sub"

      values = [
        "system:serviceaccount:kube-system:cluster-autoscaler"
      ]
    }
  }
}

# Security groups
resource "aws_iam_policy_attachment" "AmazonEKSVPCResourceController" {
  name  = "AmazonEKSVPCResourceController"
  roles = [aws_iam_role.eks_cluster.id]

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# Loadbalancer controller
data "aws_iam_policy_document" "loadbalancer_controller" {
  statement {
    effect = "Allow"

    actions = [
      "iam:CreateServiceLinkedRole"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"

      values = [
        "elasticloadbalancing.amazonaws.com"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateSecurityGroup"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateTags"
    ]

    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"

      values = [
        "CreateSecurityGroup"
      ]
    }

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"

      values = [
        "false"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]

    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"

      values = [
        "true"
      ]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"

      values = [
        "false"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"

      values = [
        "false"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"

      values = [
        "false"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags"
    ]

    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
    ]

    condition {
      test     = "Null"
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"

      values = [
        "true"
      ]
    }

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"

      values = [
        "false"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags"
    ]

    resources = [
      "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "Null"
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"

      values = [
        "false"
      ]
    }
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets"
    ]

    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule"
    ]

    resources = [
      "*"
    ]
  }
}

resource "aws_iam_policy" "loadbalancer_controller" {
  name        = "loadbalancer-controller"
  path        = "/eks/"
  description = "Loadbalancer controller policy"

  policy = data.aws_iam_policy_document.loadbalancer_controller.json
}

resource "aws_iam_policy_attachment" "loadbalancer_controller" {
  name  = "loadbalancer-controller"
  roles = [aws_iam_role.loadbalancer_controller.name]

  policy_arn = aws_iam_policy.loadbalancer_controller.arn
}

resource "aws_iam_role" "loadbalancer_controller" {
  name               = "loadbalancer-controller"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.loadbalancer_controller_assume.json
}

data "aws_iam_policy_document" "loadbalancer_controller_assume" {
  statement {

    effect = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}"
      ]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}:sub"

      values = [
        "system:serviceaccount:kube-system:aws-load-balancer-controller"
      ]
    }
  }
}

# AWS EBS CSI driver

data "aws_iam_policy_document" "ebs_csi_driver" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:AttachVolume",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteSnapshot",
      "ec2:DeleteTags",
      "ec2:DeleteVolume",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumesModifications",
      "ec2:DetachVolume",
      "ec2:ModifyVolume"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:ListKeys",
      "kms:ListAliases",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:GetPublicKey",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:CreateGrant"
    ]

    resources = [
      aws_kms_key.ebs.arn
    ]
  }
}

resource "aws_iam_policy" "ebs_csi_driver" {
  name        = "aws-ebs-csi-driver"
  path        = "/eks/"
  description = "Loadbalancer controller policy"

  policy = data.aws_iam_policy_document.ebs_csi_driver.json
}

resource "aws_iam_policy_attachment" "ebs_csi_driver" {
  name  = "aws-ebs-csi-driver"
  roles = [aws_iam_role.ebs_csi_driver.name]

  policy_arn = aws_iam_policy.ebs_csi_driver.arn
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "aws-ebs-csi-driver"
  path               = "/eks/"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_driver_assume.json
}

data "aws_iam_policy_document" "ebs_csi_driver_assume" {
  statement {

    effect = "Allow"

    principals {
      type = "Federated"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}"
      ]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${data.aws_region.current.name}.amazonaws.com/id/${local.eks_oidc_id}:sub"

      values = [
        "system:serviceaccount:kube-system:aws-ebs-csi-driver"
      ]
    }
  }
}

###
## IPFS cluster instance role
###

data "aws_iam_policy_document" "ipfs_cluster" {
  statement {
    sid    = "DescribeTagsAndVolumes"
    effect = "Allow"

    actions = [
      "ec2:DescribeTags",
      "ec2:DescribeVolumes"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    sid    = "DecodeMessages"
    effect = "Allow"

    actions = [
      "sts:DecodeAuthorizationMessage"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    sid    = "AttachDataVolumes"
    effect = "Allow"

    actions = [
      "ec2:AttachVolume"
    ]

    resources = [
      "arn:aws:ec2:*:*:instance/*",
      aws_ebs_volume.ipfs_cluster_bootstrap.arn,
      aws_ebs_volume.ipfs_cluster_peer_0.arn,
      aws_ebs_volume.ipfs_cluster_peer_1.arn
    ]
  }

  statement {
    sid    = "EBSKMS"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:ListAliases",
      "kms:Describe*",
      "kms:GenerateDataKey",
      "kms:CreateGrant"
    ]

    resources = [
      aws_kms_key.ebs.arn
    ]
  }

  statement {
    sid    = "ClusterSecrets"
    effect = "Allow"

    actions = [
      "ssm:GetParametersByPath",
      "ssm:GetParameters",
      "ssm:GetParameter"
    ]

    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/ipfs/cluster/bootstrap_address",
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/ipfs/swarm*",
      aws_ssm_parameter.ipfs_cluster_id.arn,
      aws_ssm_parameter.ipfs_cluster_private_key.arn,
      aws_ssm_parameter.ipfs_cluster_secret.arn,
    ]
  }

  statement {
    sid    = "ClusterBootstrapAddress"
    effect = "Allow"

    actions = [
      "ssm:PutParameter"
    ]

    resources = [
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/ipfs/cluster/bootstrap_address",
      "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/ipfs/swarm/*",
    ]
  }

  statement {
    sid    = "SSMKMS"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey"
    ]

    resources = [
      aws_kms_key.parameter_store.arn
    ]
  }

  statement {
    sid    = "S3KMS"
    effect = "Allow"

    actions = [
      "kms:Decrypt"
    ]

    resources = [
      aws_kms_key.s3.arn
    ]
  }

  statement {
    sid    = "S3UserData"
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.user_data_scripts.arn}/ipfs/*"
    ]
  }

  statement {
    sid    = "SessionManager"
    effect = "Allow"

    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ssm:UpdateInstanceInformation",
      "ssm:ListInstanceAssociations",
      "ssm:ListAssociations",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:DescribeAvailablePatches",
      "ssm:DescribeInstancePatchStates",
      "ssm:DescribeInstancePatchStatesForPatchGroup",
      "ssm:DescribeInstancePatches",
      "ssm:DescribePatch*",
      "ssm:GetDefaultPatchBaseline",
      "ssm:PutInventory"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "EC2Messages"
    effect = "Allow"

    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "ec2.amazonaws.com",
      ]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_policy" "ipfs_cluster" {
  name        = "ipfs-cluster"
  path        = "/ipfs/"
  description = "IPFS cluster instance policy"

  policy = data.aws_iam_policy_document.ipfs_cluster.json
}

resource "aws_iam_role" "ipfs_cluster" {
  name               = "ipfs-cluster"
  path               = "/ipfs/"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_policy_attachment" "ipfs_cluster" {
  name  = "ipfs-cluster"
  roles = [aws_iam_role.ipfs_cluster.name]

  policy_arn = aws_iam_policy.ipfs_cluster.arn
}

resource "aws_iam_instance_profile" "ipfs_cluster" {
  name = "ipfs-cluster"
  role = aws_iam_role.ipfs_cluster.name
}
