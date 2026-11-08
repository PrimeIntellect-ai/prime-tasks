E1011 when FindInMap DefaultValue is AWS::NoValue
### CloudFormation Lint Version

cfn-lint 1.3.4

### What operating system are you using?

Arch

### Describe the bug

When using the Psuedo Parameter `AWS::NoValue` as the `DefaultValue` in a `Fn::FindInMap`, an E1011 is reported.

I believe this a False Positive because `Fn::Ref` should be support for the `DefaultValue` and

> All parameters MapName, TopLevelKey, SecondLevelKey, and DefaultValue can be an intrinsic function as long as it's able to resolve to a valid value during the transform.

https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/intrinsic-function-reference-findinmap-enhancements.html#intrinsic-function-reference-findinmap-enhancements-parameters

### Expected behavior

cfn-lint does not report an E1011 when valid Intrinsic Functions are used for the DefaultValue

### Reproduction template

```yaml
Mappings:
  Roles:
    A:
     Description: "Test"

Transform: AWS::LanguageExtensions

Resources:
  Role:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !FindInMap
        - Roles
        - A
        - RoleName
        - DefaultValue: !Ref AWS::NoValue
      Description: !FindInMap
        - Roles
        - A
        - Description
        - DefaultValue: !Ref AWS::NoValue
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Principal:
              AWS: '*'
            Effect: Allow
            Action: sts:AssumeRole
```

```shell
E1011 'DefaultValue' is a required property
E1011.cfn.yaml:16:11

E1011 {'Ref': 'AWS::NoValue'} is not of type 'array', 'boolean', 'integer', 'number', 'string'
E1011.cfn.yaml:16:11
```
