SAM Function Global Environment Variables Interact Oddly with `!If` and Conditional Values
*cfn-lint version: (`cfn-lint --version`)*

cfn-lint 0.46.0

*Description of issue.*

When the `!If` intrinsic function is used with conditional values in SAM's Global Environment Variables, cfn-lint warns that the value on the `true` side of the condition may not be available when the condition is not true. For example, given an [`AWS::AppConfig::Environment`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-appconfig-environment.html) in the current template, an importable instance of same, and an environment variable meant to pass the ID of one of them to a Function:

```yaml
---
AWSTemplateFormatVersion: 2010-09-09
Transform: AWS::Serverless-2016-10-31
Parameters:
  DeploymentMode:
    Type: String
    AllowedValues:
    - sandbox
    - live
    Default: sandbox
    ConstraintDescription: Value must be a known deployment mode.
Conditions:
  IsLive: !Equals [ !Ref DeploymentMode, live ]
Globals:
  Function:
    Environment:
      Variables:
        AppConfig__Environment: !If
        - IsLive
        - !Ref ConfigEnvironment
        - !ImportValue ConfigEnvironment-blah
Resources:
  ConfigApplication:
    Type: AWS::AppConfig::Application
    Properties:
      Name: Application-A
  ConfigEnvironment:
    Type: AWS::AppConfig::Environment
    Condition: IsLive
    Properties:
      ApplicationId: !Ref ConfigApplication
      Name: Environment-B
  FunctionC:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: provided.al2
      Handler: provided
```

…cfn-lint reports this:

> [cfn-lint] W1001: Ref to resource "ConfigEnvironment" that may not be available when condition "IsLive" is False at Function/Environment/Variables/AppConfig__Environment/Fn::If/1/Ref

Oddly, the error is reported at a location in `Function` (under `Globals`, presumably), which I think isn't a location which exists in the transformed template. More oddly, this error is reported _only_ there. If the `!If` is removed and `ConfigEnvironment` is `!Ref`ed directly, the following are reported:

> [cfn-lint] W1001: Ref to resource "ConfigEnvironment" that may not be available when condition "IsLive" is False at Function/Environment/Variables/AppConfig__Environment/Ref
>
> [cfn-lint] W1001: Ref to resource "ConfigEnvironment" that may not be available when condition "IsLive" is False at Resources/FunctionC/Properties/Environment/Variables/AppConfig__Environment/Ref

That is, the error is reported both in the Globals section and in the `Environment.Variables` of `FunctionC` itself. But when the `!If` is present (as it should be), the error remains in `Globals`. If the environment variables are moved from `Globals` to directly within `FunctionC`, no error is reported. Unfortunately, this does not scale. Suppressing W1001 globally for deployments is our current workaround.

Nothing in cfn-lint jumps out at me as responsible for this issue, so I don't have any leads for you to track down. The thing that looked closest was how this section is considered to have "non-strict" values, but that appears to be related to string vs. number, so it didn't seem right to me.
