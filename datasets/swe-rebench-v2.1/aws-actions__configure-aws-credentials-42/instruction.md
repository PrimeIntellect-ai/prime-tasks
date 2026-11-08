Optional AWS_ACCESS_KEY_ID and AWS_SECRET_ACCES_KEY when relying on IAM Roles
I'm using my own self-hosted runner which runs in AWS. The runner instance has IAM Role which takes care of the all the credentials and policies so I don't need to store any AWS credentials outside AWS.

The IAM role allows the runner to do a 'aws sts assume-role' but doesn't need any credentials (uses IAM role).
I would like to use  this Github Action to do the assume-role, instead of scripting it myself and set the credential output as environment variable so I can use them in all the following steps, but currently AWS_ACCESS_KEY_ID and AWS_SECRET_ACCES_KEY are required. I would like to them to be optional so it fits the use case when using IAM roles which is a best-practice.

### Additional contract requirements

The action metadata file `action.yml` must declare the `aws-access-key-id` and
`aws-secret-access-key` inputs as optional: neither input may be marked
`required: true`. This is what makes the credentials optional for workflow users
who rely on IAM-role credentials.
