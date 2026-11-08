[Bug] EKS is not integrated with OIDC Provider, but it's doing Get OpenID call
EKS is not integrated with OIDC Provider, but it's doing Get OpenID call because of which the deletion is failing. The main issue is this role is blocked by the IT team

```
eksctl version 0.97.0
using region us-east-1
deleting EKS cluster "test"
will drain 0 unmanaged nodegroup(s) in cluster "test"
deleted 0 Fargate profile(s)
kubeconfig has been updated
cleaning up AWS load balancers created by Kubernetes objects of Kind Service or Ingress
Error: operation error IAM: GetOpenIDConnectProvider, https response error StatusCode: 403, RequestID: e08bc362-77c7-4aba-a5cb-9e888885b484, api error AccessDenied: User: arn:aws:sts::485443633092:assumed-role/EksctlRole-BCGSSRVAC970/AWSCodeBuild-670ebbbbbbbbbb3d-7a3ba6ee3300 is not authorized to perform: iam:GetOpenIDConnectProvider on resource: arn:aws:iam::00000000:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/4FC3F00000797DAEAF1103D8027 with an explicit deny in a permissions boundary
````

### Additional contract requirements

- When the lookup of the cluster's IAM OIDC provider is denied (an AccessDenied error from IAM) and the cluster has no IAM service accounts, deleting the cluster must not fail because of that denied lookup. The deletion should complete and remove the cluster's other resources.
