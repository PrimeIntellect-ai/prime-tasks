iam.IAMRole.AssumeRolePolicyDocument: IsUpToDate fails, constandly updating
### What happened?
IAMRole is constantly updating because the policy order changes

With the following policy:
```yaml
{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Principal":{
                "Federated":"arn:aws:iam::...:oidc-provider/oidc.eks.eu-north-1.amazonaws.com/id/..."
            },
            "Action":"sts:AssumeRoleWithWebIdentity",
            "Condition":{
                "StringEquals":{
                    "oidc.eks.eu-north-1.amazonaws.com/id/...:a":"system:serviceaccount:default:app",
                    "oidc.eks.eu-north-1.amazonaws.com/id/...:b":"sts.amazonaws.com"
                }
            }
        }
    ]
}
```

I see that the two map elements in `StringEquals` changes order.

### How can we reproduce it?
See policy above.

### What environment did it happen in?
Crossplane version: 0.19.0
EKS 1.21

### Additional contract requirements

- Add a public function `IsPolicyUpToDate(local, remote *string) bool` in package `pkg/clients` (import path `github.com/crossplane/provider-aws/pkg/clients`). Both pointers are non-nil. It returns `true` when the two JSON policy documents are semantically identical, ignoring differences in field or slice ordering, and `false` otherwise. If either document cannot be unmarshalled as JSON, it returns `false`.
- `IsRoleUpToDate(in v1beta1.IAMRoleParameters, observed iam.Role) (bool, string, error)` in package `pkg/clients/iam` (import path `github.com/crossplane/provider-aws/pkg/clients/iam`) reports whether an existing IAM role matches the desired parameters. It compares the `AssumeRolePolicyDocument` contents ignoring ordering differences. It returns an empty diff string when the role is up to date and a non-empty human-readable diff otherwise, and it returns a non-nil error when the `AssumeRolePolicyDocument` cannot be processed, for example when it cannot be unescaped.
