Add support for AWS ECR Public in `ECRAuthorizationToken` generator
**Is your feature request related to a problem? Please describe.**
The `ECRAuthorizationToken` generator kind seems to only be able to get a private ECR authorization token. This token is only valid for private registries within the AWS account. If you would like to use the AWS ECR Public Gallery, there is a separate API and IAM permission associated with it that needs to be used.

The AWS CLI command is as follows for logging in to such a registry:

`aws ecr-public get-login-password --region us-east-1`

Note the use of `ecr-public` vs `ecr`, and the region I believe has to be `us-east-1` (global).

**Describe the solution you'd like**
The ability to manage AWS ECR Public authorization tokens via `external-secrets`. This would greatly simplify credential management for OCI repositories which are hosted in the AWS public gallery. Right now its a mess of cronjobs to try and fudge it.

**Describe alternatives you've considered**
One solution might be the implementation of an `ECRPublicAuthorizationToken` kind. I don't really know enough about the implementation to know whether or not adding a `scope: <private|public>` to the `spec` might be possible while still using an `ECRAuthorizationToken`.

**Additional context**
The `ecrpublic` service appears to have dedicated support in the AWS SDK for it:

https://github.com/aws/aws-sdk-go/tree/main/service/ecrpublic

I would have a go at trying to implement something, but fear the result would be somewhat crude.
