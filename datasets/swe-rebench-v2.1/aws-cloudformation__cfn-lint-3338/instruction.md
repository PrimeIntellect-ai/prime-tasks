E3677 'provided.al2023' does not match '^(nodejs.*|python.*)$'
### CloudFormation Lint Version

1.3.0

### What operating system are you using?

Mac

### Describe the bug

Following upgrading to the 1.3.0 version of the linter, we have seen the following failure on our Lambda function configured using CloudFormation:
```
E3677 'provided.al2023' does not match '^(nodejs.*|python.*)$'
```
The supported runtimes as documented by AWS (https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html#runtimes-supported) specifies that the provided.al2023 is supported and therefore should be not fail the lint checks

### Expected behavior

No failure when using provided.al2023

### Reproduction template

```yaml
  LambdaFunction:
    Type: AWS::Lambda::Function
    DependsOn: LambdaPolicy
    Properties:
      Architectures:
        - arm64
      Code: ../link/to/my/package.zip
      Description: My description
      Handler: my.bootstrap.file
      MemorySize: 1024
      Role:
        Fn::GetAtt:
          - LambdaRole
          - Arn
      Runtime: provided.al2023
```
