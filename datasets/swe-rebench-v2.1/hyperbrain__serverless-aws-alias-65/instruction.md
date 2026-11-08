Support deployment bucket server side encryption
As Serverless now can be configured to use server side encryption for a pre existing deployment bucket, can we use the same for this plugin?

### Additional contract requirements

The plugin must apply the deployment bucket's server-side encryption configuration to the
S3 `putObject` request it issues when uploading the compiled alias CloudFormation template.

The configuration is read from the Serverless service provider's deployment bucket object
(`serverless.service.provider.deploymentBucketObject`). When that object is present, the
following keys are forwarded to the S3 `putObject` parameters under the given names:

- `serverSideEncryption` maps to `ServerSideEncryption`
- `sseKMSKeyId` maps to `SSEKMSKeyId`
- `sseCustomerAlgorithm` maps to `SSECustomerAlgorithm`
- `sseCustomerKey` maps to `SSECustomerKey`
- `sseCustomerKeyMD5` maps to `SSECustomerKeyMD5`

Only these keys are forwarded; any other keys present in the deployment bucket object are
ignored. When no deployment bucket object is configured, the S3 `putObject` parameters are
left unchanged.
