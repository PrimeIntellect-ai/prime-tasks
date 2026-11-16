Enhance the assumeRoleARN authentication to apply session tags in AWS STS
### What problem are you facing?
We are creating a provider config per namespace and are trying to create a scalable way to provide the correct amount of access to the aws-provider for each configuration.  The process we use outside of crossplane is to have an IAM user (could be a role) in one account and it can assume some default roles that are in all of our other accounts.  Those roles look at session tags to make sure that what you are deploying/changing have the same tag on the resource you are creating or deploying.

### How could Crossplane help solve your problem?

If crossplane (aws-provider) was able to pass tags to the STS session, we would be able to use our standard roles in all of the accounts that we have.  It would make it so much easier to scale.

### Additional contract requirements

A ProviderConfig may specify session tags under `spec.assumeRole.tags` as a list of `{key, value}` pairs. When the provider assumes the configured role, it must include those pairs in the AWS STS AssumeRole session. Existing role assumption using the deprecated `spec.assumeRoleARN` configuration must continue to work.
