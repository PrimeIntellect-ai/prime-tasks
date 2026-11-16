API Gateway Lambda authorizer URI incorrectly fails I3042:accountId check
### CloudFormation Lint Version

1.12.4

### What operating system are you using?

Mac/Ubuntu

### Describe the bug

cfn-lint expects the `:lambda:` segment of the API Gateway Lambda authorizer URI to not be a hardcoded account ID, when the `:lambda:` segment should be hardcoded to `lambda`.

```
$ cfn-lint --format pretty --regions us-east-2 --include-checks I --configure-rule E3012:strict=True I3042:region=True I3042:accountId=True -- template.yaml
template.yaml
6:7:                I3042     ARN in Resource Resource contains hardcoded AccountId in ARN or incorrectly placed Pseudo Parameters
```

### Expected behavior

API Gateway Lambda authorizer URI doesn't fail I3042:accountId check

### Reproduction template

```yaml
AWSTemplateFormatVersion: 2010-09-09
Resources:
  Resource:
    Type: AWS::ApiGateway::Authorizer
    Properties:
      AuthorizerUri: !Sub arn:${AWS::Partition}:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/arn:${AWS::Partition}:lambda:${AWS::Region}:${AWS::AccountId}:function:Name/invocations
      RestApiId: RestApiId
      Type: REQUEST
      Name: Name
```
