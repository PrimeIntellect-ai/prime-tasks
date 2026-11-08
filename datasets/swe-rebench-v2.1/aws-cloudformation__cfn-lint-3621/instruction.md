E3002, E3031 & E3512 for Policy statement with Assumed-role session principals
### CloudFormation Lint Version

1.10.1

### What operating system are you using?

Mac

### Describe the bug

When I use Assumed-role session principals inside Policy statements, I get multiple false positives:

```
E3002 '*' was expected
test-cfn.yml:11:15

E3031 'arn:aws:sts::1234:assumed-role/rolename/rolesessionname' does not match '^\\d{12}$'
test-cfn.yml:11:15

E3031 'arn:aws:sts::1234:assumed-role/rolename/rolesessionname' does not match '^arn:(aws|aws-cn|aws-us-gov):iam::\\d{12}:(?:root|user|group|role)'
test-cfn.yml:11:15

E3031 'arn:aws:sts::1234:assumed-role/rolename/rolesessionname' does not match '^arn:(aws|aws-cn|aws-us-gov):iam::cloudfront:user/.+$'
test-cfn.yml:11:15

E3512 'arn:aws:sts::1234:assumed-role/rolename/rolesessionname' is not valid under any of the given schemas
test-cfn.yml:11:15
```

### Expected behavior

Assumed-role session principals should be supported too as described here: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_principal.html#principal-sessions

Format seems to be: `arn:aws:sts::<AWS-account-ID>:assumed-role/<role-name>/<role-session-name>`

### Reproduction template

```yaml
Resources:
  TestBucketPolicy:
    Type: 'AWS::S3::BucketPolicy'
    Properties:
      Bucket: 'bucket'
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Sid: 'test-sid'
            Principal:
              AWS: 'arn:aws:sts::1234:assumed-role/rolename/rolesessionname'
            Action: 's3:ListBucket'
            Effect: Allow
            Resource:
              - 'arn:aws:s3:::bucket'
```
