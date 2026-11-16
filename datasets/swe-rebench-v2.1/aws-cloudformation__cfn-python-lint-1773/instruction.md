Using ImportValue skips List type resource validation
*cfn-lint version: (`cfn-lint --version`)*
cfn-lint 0.40.0

*Description of issue.*
When we use [`Fn::ImportValue`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-importvalue.html) for a resource key that needs type List, it accepts a scalar value and cfn-lint doesn't fail. But when we use scalar value directly it works as expected and fails.

Following template needs `SubnetIds` and `SecurityGroupIds` as list of Strings (https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-lambda-function-vpcconfig.html), but using ImportValue masks the error and linting does not fail as expected

Template that should fail but succeeds
```yaml
Resources:
  LambdaFunction:
    Type: 'AWS::Lambda::Function'
    Properties:
      Runtime: java8
      Code:
        S3Bucket: 'foo-bar'
        S3Key: 'foo-bar'
        S3ObjectVersion: 'foo-bar'
      Handler: 'com.foo.bar::handleRequest'
      Role: 'arn:aws:iam::123456789101:role/foo-bar'
      VpcConfig:
        SubnetIds: !ImportValue foobar1
        SecurityGroupIds: !ImportValue foobar2
```

Template that fails correctly
```yaml
Resources:
  LambdaFunction:
    Type: 'AWS::Lambda::Function'
    Properties:
      Runtime: java8
      Code:
        S3Bucket: 'foo-bar'
        S3Key: 'foo-bar'
        S3ObjectVersion: 'foo-bar'
      Handler: 'com.foo.bar::handleRequest'
      Role: 'arn:aws:iam::123456789101:role/foo-bar'
      VpcConfig:
        SubnetIds: 'foobar1'
        SecurityGroupIds: 'foobar2'

E3002 Property SubnetIds should be of type List for resource LambdaFunction
lambda-function.yaml:14:9

E3002 Property SecurityGroupIds should be of type List for resource LambdaFunction
lambda-function.yaml:15:9
```
