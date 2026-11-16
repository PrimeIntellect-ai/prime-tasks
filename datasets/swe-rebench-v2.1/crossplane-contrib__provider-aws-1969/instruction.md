IAM Role possible update-loop due to `RoleLastUsed`
### What happened?

Similar to this `iam.Role` issue https://github.com/crossplane-contrib/provider-aws/issues/1945, the **observed** parameter `RoleLastUsed` can lead to update-loops if AWS sets it. (only set on AWS SDK/CLI usage of role?)

from the provider-aws debug logs:

```
"Found observed difference in IAM role
  &types.Role{
   ... // 2 ignored and 5 identical fields
   MaxSessionDuration:  &3600,
   PermissionsBoundary: nil,
   RoleLastUsed: &types.RoleLastUsed{
-      LastUsedDate: &s\"0001-01-01 00:00:00 +0000 UTC\",
+      LastUsedDate: &s\"2023-12-06 14:30:40 +0000 UTC\",
       Region:       &\"eu-central-1\",
       ... // 1 ignored field
   },
   ...
 }"
```

EDIT: I will try to provide a PR.

### How can we reproduce it?
1. Create `iam.Role`
2. use Role so AWS sets a LastUsedDate/"Last activity"(== parameter display name in AWS Management Console) value
3. get update-loop

### What environment did it happen in?
Crossplane version: v1.14.3
provider-aws: v0.45.2 + master
