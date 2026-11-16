ECR Policy interaction with AWS causes update loops
### What happened?
Implementing ECR Repository Policies atop some existing ECR Repo definitions, I was using the `accountId` principal to set permissions for a repo from particular AWS accounts.

I was notified this morning of excess AWS Config charges from calls to `SetRepositoryPolicy`: 700,000 over the course of 10 days per Repo 😄

Digging around, it looks like there's 2 cases where the ECR Repository Policy does not correctly detect the resource as up to date, and repeatedly triggers an Update call:

1. When using the `awsAccountId` principal, AWS documentation says you can specify either the plain account ID, OR the ARN of the root of the account, i.e. the below, but AWS converts the raw account ID to an ARN string internally and appears to _always_ return the ARN. `SerializeAWSPrincipal` just returns the plain user input as a string, so if the user specifies a plain account ID rather than an ARN, these will never be detected as up to date.
    - `"Principal": { "AWS": "arn:aws:iam::123456789012:root" }` or
    - `"Principal": { "AWS": "123456789012" }` are functionally equal.
2. Principals are not sorted before or during comparison, so if AWS returns the principals in a different order to the user input they will also never be detected as up to date.

### How can we reproduce it?
Create an ECR repo (settings unimportant), and then create a `RepositoryPolicy` referring to it with the following:
```yaml
apiVersion: ecr.aws.crossplane.io/v1alpha1
kind: RepositoryPolicy
metadata:
  name: my-never-uptodate-policy
spec:
  forProvider:
    policy:
      id: AllowAccounts
      statements:
      - action:
        - ecr:BatchCheckLayerAvailability
        - ecr:BatchGetImage
        - ecr:GetDownloadUrlForLayer
        effect: Allow
        principal:
          awsPrincipals:
          - awsAccountId: 123456789012
          - awsAccountId: arn:aws:iam::123456789013:root
        sid: AllowPull
      version: "2008-10-17"
    region: us-east-1
    repositoryName: <name-of-your-ecr-repo>
```

The status object of the resource will look something like this:

```yaml
status:
  atProvider:
    policyText: |-
      {
        "Version" : "2008-10-17",
        "Id" : "AllowAccounts",
        "Statement" : [ {
          "Sid" : "AllowPull",
          "Effect" : "Allow",
          "Principal" : {
            "AWS" : [ "arn:aws:iam::123456789013:root", "arn:aws:iam::123456789012:root" ]
          },
          "Action" : [ "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer" ]
        } ]
      }
```

Note that the principals are always an ARN and they're not in the same order as specified by the resource.

### What environment did it happen in?
AWS Provider version: v0.18.1

### Suggested fix
[HIDDEN]

[HIDDEN]

Happy to submit a PR for these if approach makes sense.
