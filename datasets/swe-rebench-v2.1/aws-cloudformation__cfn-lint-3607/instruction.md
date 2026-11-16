E3057 does not check if a TargetGroupID value is a valid OriginGroup.
### CloudFormation Lint Version

1.10.2

### What operating system are you using?

Mac

### Describe the bug

E3057 is a false positive if a valid OriginGroup is specified as the TargetOriginID. The new rule only checks if the TargetOriginID is a valid TargetOrigin, but doesn't also check if the value is a valid OriginGroup.
https://github.com/aws-cloudformation/cfn-lint/pull/3561

### Expected behavior

The lint rule should also check if a TargetOriginID value is a valid OriginGroup.

### Reproduction template

```
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  MyS3BucketPrimary:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: my-primary-bucket

  MyS3BucketSecondary:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: my-secondary-bucket

  MyCloudFrontDistribution:
    Type: AWS::CloudFront::Distribution
    Properties:
      DistributionConfig:
        Origins:
          - Id: PrimaryS3Origin
            DomainName: !GetAtt MyS3BucketPrimary.DomainName
            S3OriginConfig:
              OriginAccessIdentity: ""
          - Id: SecondaryS3Origin
            DomainName: !GetAtt MyS3BucketSecondary.DomainName
            S3OriginConfig:
              OriginAccessIdentity: ""
        OriginGroups:
          Quantity: 1
          Items:
            - Id: MyOriginGroup
              FailoverCriteria:
                StatusCodes:
                  Quantity: 1
                  Items:
                    - 403
              Members:
                Quantity: 2
                Items:
                  - OriginId: PrimaryS3Origin
                  - OriginId: SecondaryS3Origin
        DefaultCacheBehavior:
          TargetOriginId: MyOriginGroup
          ViewerProtocolPolicy: redirect-to-https
          AllowedMethods: ['GET', 'HEAD', 'OPTIONS']
          CachedMethods: ['GET', 'HEAD', 'OPTIONS']
          ForwardedValues:
            QueryString: false
            Cookies:
              Forward: none
        Enabled: true

Outputs:
  CloudFrontDistributionId:
    Description: "CloudFront Distribution ID"
    Value: !Ref MyCloudFrontDistribution
  CloudFrontDomainName:
    Description: "CloudFront Domain Name"
    Value: !GetAtt MyCloudFrontDistribution.DomainName
```
