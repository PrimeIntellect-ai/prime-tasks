ECR RepositoryPolicy constantly reconciles
### What happened?
Seeing a very high rate (upwards of 10 per minute per resource) of reconciles for `repositorypolicy.ecr.aws.crossplane.io` against `provider-aws` master, even though all policies exist, are up to date and not late-initialized.

Given that there can only be one policy per repository, I would expect to see a similar reconcile rate as seen with repositories but this is not the case.

It looks like this is caused by the AWS API constantly returning array items inside my repository policy (in this case AWS Principals) in a different order. I've confirmed this locally - no two subsequent calls to `aws ecr get-repository-policy` for a particular repository returns the same policy order.

This is correctly ignored by `provider-aws` and marked as up to date (as we ignore sort order when comparing the policy as of #701), but it looks like when the controller persists the 'updated' resource `status` back to the Kubernetes API, it causes the requeue period that `provider-aws` requested to be ignored, and the resource is requeued straight away.

This ends up in an endless loop of updates that has some other nasty side effects like blowing out the AWS SDK connection pool.

### How can we reproduce it?

Apply an ECR `repositorypolicy` with the following spec, with many different AWS account ID's:

```yaml
spec:
   deletionPolicy: Delete
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
           - awsAccountId: arn:aws:iam::3398....7229:root
           - awsAccountId: arn:aws:iam::9718....6735:root
           - awsAccountId: arn:aws:iam::8433....0030:root
           - awsAccountId: arn:aws:iam::4883....5958:root
           - awsAccountId: arn:aws:iam::9418....5648:root
           - awsAccountId: arn:aws:iam::3468....4853:root
         sid: AllowPullNonProdAccounts
       version: "2008-10-17"
     region: us-east-1
```

And then monitor the number of reconciles. I worked out what was going on by dumping the policy inside kubernetes at set intervals and then diffing the yaml output.

### What environment did it happen in?
Crossplane version: v1.3
Provider-AWS version: 009f048d509ba924ce6c456740ab946666a49bb6

### Fix
I wonder if `policyText` should even be available on this resource, as this is just a different representation of a user-defined setting and the resource should be updated if these don't match.

### Additional contract requirements

- After observing a repository policy, `status.atProvider` must be empty; do not record the AWS-returned policy text in `status.atProvider.policyText`.
