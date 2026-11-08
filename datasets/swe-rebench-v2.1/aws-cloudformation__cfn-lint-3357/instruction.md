E3002, E3031 & E3512 for AWS::S3::BucketPolicy with OAI
### CloudFormation Lint Version

1.3.0+ (git a7906eaaa)

### What operating system are you using?

Mac

### Describe the bug

CFN template with an S3 BucketPolicy referencing a CloudFront Origin Access Identity raises 3 errors in cfn-lint v1

```
E3002 '*' was expected
oai.yaml:11:13

E3512 {'AWS': ['arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E1234ABCDE12AB']} is not valid under any of the given schemas
oai.yaml:11:13

E3031 'arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E1234ABCDE12AB' does not match '^((arn:(aws|aws-cn|aws-us-gov):iam::\\d{12}:(?:root|user|group|role)|\\*)|\\d{12})'
oai.yaml:13:17
```


### Expected behavior

No errors

### Reproduction template

```
AWSTemplateFormatVersion: "2010-09-09"
Resources:
  DestinationS3BucketPolicy:
    Type: 'AWS::S3::BucketPolicy'
    Properties:
      Bucket: 'bucket'
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Sid: 'cfn-lint-v1'
            Principal:
              AWS:
              - 'arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E1234ABCDE12AB'
            Action: 's3:ListBucket'
            Effect: Allow
            Resource:
              - 'arn:aws:s3:::bucket'
```
