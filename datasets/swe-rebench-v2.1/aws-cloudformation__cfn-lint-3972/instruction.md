Feature Request: `AWS::CodeBuild::Project` - recognize if 2 resources have the same `Name`
### Is this feature request related to a new rule or cfn-lint capabilities?

_No response_

### Describe the feature you'd like to request

It would be great if cfn-lint would recognize if a `AWS::CodeBuild::Project` has the same name as another `AWS::CodeBuild::Project` - which will cause a deployment failure:

```yaml
Project1:
  Type: AWS::CodeBuild::Project
  Properties:
    Name: myProjectName
    ServiceRole: !GetAtt ServiceRole.Arn
    Artifacts:
      Type: no_artifacts
    Environment:
      Type: LINUX_CONTAINER
      ComputeType: BUILD_GENERAL1_SMALL
      Image: aws/codebuild/java:openjdk-8
      EnvironmentVariables:
      - Name: varName
        Type: varType
        Value: varValue
    Source:
      Location: codebuild-demo-test/0123ab9a371ebf0187b0fe5614fbb72c
      Type: S3
    TimeoutInMinutes: 10

Project2:
  Type: AWS::CodeBuild::Project
  Properties:
    Name: myProjectName
    ServiceRole: !GetAtt ServiceRole.Arn
    Artifacts:
      Type: no_artifacts
    Environment:
      Type: LINUX_CONTAINER
      ComputeType: BUILD_GENERAL1_SMALL
      Image: aws/codebuild/java:openjdk-8
      EnvironmentVariables:
      - Name: varName
        Type: varType
        Value: varValue
    Source:
      Location: codebuild-demo-test/0123ab9a371ebf0187b0fe5614fbb72c
      Type: S3
    TimeoutInMinutes: 10
```

### Describe the solution you'd like

cfn-lint throws an error that both resources have the same name.

### Additional context

_No response_

### Is this something that you'd be interested in working on?

- [ ] 👋 I may be able to implement this feature request

### Would this feature include a breaking change?

- [ ] ⚠️ This feature might incur a breaking change
