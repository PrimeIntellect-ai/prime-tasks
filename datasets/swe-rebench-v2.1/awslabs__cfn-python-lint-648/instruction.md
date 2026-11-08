E3002 received when using Fn::GetAtt in an Fn::If for a property that should be a list
*cfn-lint version: (0.13.2)*

*E3002 false positive when using Fn::If and Fn::GetAtt in an AWS::CodeBuild::Project's EnvironmentVariables*

Please provide as much information as possible:
* Template linting issues:
  * Please provide a CloudFormation sample that generated the issue.

Spec Override:
```json
{
  "ResourceTypes": {
    "Custom::EnvironmentVariables": {
      "Documentation": "https://github.com/IntuitiveWebSolutions/BriteDevelopment/blob/master/CustomResources.md#yaml-parser",
      "Properties": {
        "ServiceToken": {
          "PrimitiveType": "String",
          "Required": true,
          "UpdateType": "Immutable"
        },
        "String": {
          "PrimitiveType": "String",
          "Required": true,
          "UpdateType": "Mutable"
        }
      },
      "Attributes": {
        "Variables": {
          "ItemType": "AWS::CodeBuild::Project.EnvironmentVariable",
          "Type": "List"
        }
      }
    }
  },
  "ResourceSpecificationVersion": "2.11.0"
}
```

Example template:
```yaml
Conditions:
  ConditionTrue:
    Fn::Equals:
      - ""
      - ""

Resources:

  MyCustomEnvironmentVariables:
    Type: Custom::EnvironmentVariables
    Properties:
      ServiceToken:
        Fn::ImportValue: "MyServiceToken"
      String: "envvar1=1, envvar2=2"

  ProjectBuild:
    Type: AWS::CodeBuild::Project
    Properties:
      Name: "My Project"
      Description: "My Description"
      Artifacts:
        Type: CODEPIPELINE
      ServiceRole:
        Fn::ImportValue: "ServiceRole"
      Environment:
        ComputeType: BUILD_GENERAL1_SMALL
        Image: aws/codebuild/python:3.7.1
        Type: LINUX_CONTAINER
        EnvironmentVariables:
          Fn::If:
            - ConditionTrue
            - Fn::GetAtt: [MyCustomEnvironmentVariables, Variables]
            - Ref: AWS::NoValue
      Source:
        BuildSpec: buildspec.yaml
        Type: CODEPIPELINE
```
  * If present, please add links to the (official) documentation for clarification.

The Custom::EnvironmentVariables sets the value of the attribute `Variables` with a list of items meeting the definition of `AWS::CodeBuild::Project.EnvironmentVariable` found [here](https://raw.githubusercontent.com/awslabs/cfn-python-lint/master/src/cfnlint/data/CloudSpecs/us-east-1.json)

* Bug Report:
The above CloudFormation is valid, however, cfn-lint gripes with E3002 when using a conditional statement to set `EnvironmentVariables` to the <List> attribute provided by the `Custom::EnvironmentVariables` resource.

Example usage:
$ cfn-lint -o specs.json example.yaml
E3002 Property EnvironmentVariables should be of type List for resource ProjectBuild at Resources/ProjectBuild/Properties/Environment/EnvironmentVariables/Fn::If/1
example.yaml:30:11

In cfnlint/rules/resources/properties/Properties.py:100 d_k is "Fn::GetAtt" and d_v is ['MyCustomEnvironmentVariables', 'Variables'] which results in the false positive being emitted.
