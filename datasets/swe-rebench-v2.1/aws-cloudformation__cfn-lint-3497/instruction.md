Lambda: AutoPublishCodeSha256 invalid must be string
### CloudFormation Lint Version

1.6.0

### What operating system are you using?

Mac

### Describe the bug

In a lambda resource passing a string parameter to the AutoPublishCodeSha256 properties, results in the following error:

E0001 Error transforming template: Resource with id [LambdaFunctionAcquireSftp] is invalid. AutoPublishCodeSha256 must be a string
stack.yaml:1:1

This basically stops linting checks in the rest of the template. Here is the exact lambda property:

AutoPublishCodeSha256: !Ref GitCommit

GitCommit is a string parameter in the template. The template builds successfully, its just the linting that fails. Should also be noted the resource is AWS::Serverless::Function.

Very basic template shown below.

### Expected behavior

This should not flag the template as invalid.

### Reproduction template

---
Transform: AWS::Serverless-2016-10-31
Parameters:
  Basepath:
    Type: String
  CodeBucket:
    Type: String
  GitCommit:
    Type: String
Resources:
  LambdaFunction:
    Type: AWS::Serverless::Function
    Properties:
      AutoPublishAlias: live
      AutoPublishCodeSha256: !Ref GitCommit
      CodeUri:
        Bucket: !Ref CodeBucket
        Key: !Sub ${ Basepath }/lambda.zip
      DeploymentPreference:
        Enabled: false
      FunctionName: !Sub ${ AWS::StackName }
      Handler: lambda.handler
      MemorySize: 256
      Role: !GetAtt IamRole.Arn
      Runtime: python3.12
      Timeout: 30
      Tracing: PassThrough
