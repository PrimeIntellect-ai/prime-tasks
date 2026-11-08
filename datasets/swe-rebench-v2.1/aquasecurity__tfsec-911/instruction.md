AWS068 should not be flagged when public access to EKS API server is disabled
AWS068 - EKS cluster should not have open CIDR range for public access

In EKS, there is an option to disable public access to the API server.  When public access is disabled, I think AWS068 should not be flagged.
i.e. the following code should pass the check
```terraform
resource "aws_eks_cluster" "private_cluster" {
    name = "private_cluster"
    role_arn = var.cluster_arn
    vpc_config {
        endpoint_public_access = false
    }
}
```

Relevant docs:
https://tfsec.dev/docs/aws/eks/no-public-cluster-access-to-cidr/
https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster#vpc_config-arguments

### Additional contract requirements

Do not report AWS068 when public access to the EKS API server is disabled, regardless of the configured public-access CIDR. When public access is enabled, continue to report AWS068 for an open public-access CIDR.
