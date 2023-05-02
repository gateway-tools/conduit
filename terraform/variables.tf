variable "cluster_name" {
  type    = string
  default = "ipfs-default"
}

variable "desired_nodes" {
  type    = number
  default = 1
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 5
}

variable "internal_domain" {
  type        = string
  description = "Internal domain"

  validation {
    condition = length(var.internal_domain) >= 4
    error_message = "Internal domain can't be less than 4 characters."
  }
}

variable "eks_cluster_security_group" {
  type        = list(string)
  description = "EKS cluster security group IDs"
}

variable "ipv6_cidr" {
  type        = list(string)
  description = "IPv6 VPC CIDR block"
}

variable "app_lb_dns" {
  type        = list(string)
  description = "Primary application/network loadbalancer DNS name"
}

variable "public_domain" {
  type = string
  description = "Public domain"

  validation {
    condition = length(var.public_domain) >= 4
    error_message = "Public domain can't be less than 4 characters or left undefined."
  }
}

variable "ipfs_volume_size" {
  type = number
  default = 120
  description = "IPFS node volume size."
}

variable "ipfs_volume_iops" {
  type = number
  default = 8000
  description = "IOPS for IPFS node volume"

  validation {
    condition = var.ipfs_volume_iops <= 10000 && var.ipfs_volume_iops >= 300
    error_message = "IOPS should be within range of 300 and 10000."
  }
}

variable "ipfs_instance_type" {
  type = string
  default = "m5.large"
  description = "IPFS cluster node size."
}

variable "ssh_cidr_blocks" {
  type = list(string)
  description = "list of CIDR blocks to allow ssh from"
}

variable "ipfs_cluster_secret" {
  type = string
  description = "IPFS cluster secret. Generate it with 'od  -vN 32 -An -tx1 /dev/urandom | tr -d ' \n' | base64 -w 0 -' before running this module and save for future usage"

}

variable "ipfs_cluster_key" {
  type = string
  description = "IPFS cluster key. Generate it (and matching key ID) with 'ipfs-key -type ed25519 | base64 -w 0' before running this module and save for future usage"
}

variable "ipfs_cluster_key_id" {
  type = string
  description = "IPFS cluster key ID. Generate it (and matching key) with 'ipfs-key -type ed25519 | base64 -w 0' before running this module and save for future usage"
}

variable "private_subnet_ids" {
  type = list(string)
  description = "List of private subnet IDs"
}

variable "public_subnet_ids" {
  type = list(string)
  description = "List of public subnet IDs"
}

variable "azs" {
  type = list(string)
  description = "List of availability zones to deploy in"
}

variable "vpc_id" {
  type = string
  description = "ID of VPC to deploy to"
}
