False Positive for Primary Identifiers E3019 When using Fn::ForEach and value from a Mapping
### CloudFormation Lint Version

cfn-lint 1.3.3

### What operating system are you using?

Arch

### Describe the bug

Using Fn::ForEach to generate Resources cfn-lint reports that the PrimaryIdentifier is not unique across resources. I've only tried this with `AWS::IAM::Role` so not sure how many Resource Types this affects.

```shell
E3019 Primary identifiers {'RoleName': 'Bravo'} should have unique values across the resources {'A', 'B'}
```

### Expected behavior

When using Fn::ForEach cfn-lint should evaluate that PrimaryIdentifiers are unique.

### Reproduction template

```yaml
Mappings:
  Roles:
    A:
      RoleName: Alpha
    B:
      RoleName: Bravo


Transform: AWS::LanguageExtensions

Resources:
  Fn::ForEach::TestRole:
    - Role
    - - A
      - B
    - ${Role}:
        Type: AWS::IAM::Role
        Properties:
          RoleName: !FindInMap
            - Roles
            - !Ref Role
            - RoleName
          AssumeRolePolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Principal:
                  AWS: '*'
                Effect: Allow
                Action: sts:AssumeRole
```

This only seems to occur when using a Mapping - the following does **not** produce an E3019

```yaml
Transform: AWS::LanguageExtensions

Resources:
  Fn::ForEach::TestRole:
    - Role
    - - A
      - B
    - ${Role}:
        Type: AWS::IAM::Role
        Properties:
          RoleName: !Ref Role
          AssumeRolePolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Principal:
                  AWS: '*'
                Effect: Allow
                Action: sts:AssumeRole
```
