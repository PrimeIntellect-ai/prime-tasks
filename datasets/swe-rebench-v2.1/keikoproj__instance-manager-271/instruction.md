Remove AmazonEKS_CNI_Policy from DefaultManagedPolicies
AmazonEKS_CNI_Policy is currently part of DefaultManagedPolicies, which are automatically added to the roles created and associated with nodes provisioned by the EKS provisioner.

In the AWS docs, it is recommended to remove it and use IAM Roles for Service Accounts instead.
We should remove it from the defaults or offer a way for users to opt-out of attaching it.

### Additional contract requirements

The opt-out is offered through an instance group annotation:

- Annotation key: `instancemgr.keikoproj.io/irsa-enabled`
- When the annotation value is `"true"` (case-insensitive), the `AmazonEKS_CNI_Policy` managed policy must not be attached to the node role.
- When the annotation is absent or has any other value, `AmazonEKS_CNI_Policy` is attached by default.

The managed policies attached to a node role by default are therefore:

- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy` (only when IRSA is not enabled as described above)
