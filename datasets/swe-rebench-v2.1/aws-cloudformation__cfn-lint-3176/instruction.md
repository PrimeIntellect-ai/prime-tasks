Validaton error for `Fn::ForEach` - `contains invalid characters`
### CloudFormation Lint Version

cfn-lint 0.86.4

### What operating system are you using?

Ubuntu

### Describe the bug

I am getting false validation errors when using `Fn::ForEach` :

```
E3031 TargetId contains invalid characters (Pattern: \d{12}) at Resources/SystemAdminAssignmentCFcfhIH/Properties/TargetId
```

I am not 100% this is a bug since I am not able (at least not that I am aware of) set a type for the values.

I wasn't able to locate how to define values for this test.  This would explain the issue as I am seeing it using `CFcfhIH` as the value when this should be an id.

Perhaps I am missing something?

### Expected behavior

I expected this to not throw a validation error. I have this same issue in all templates that use `Fn::ForEach`.

### Reproduction template

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: 'AWS::LanguageExtensions'

Description: Configures IAM Identity Center. IAM Identity Center must be enabled before you create this stack.

Parameters:

  IamIdentityCenterInstanceArn:
    Type: String
    Description: 'The ARN for the IAM Identity Center Instance. Found in the settings of IAM Identity Center.'

  IdentityStoreId:
    Type: String
    Description: 'The id for the identity store. Found in the settings of IAM Identity Center.'

  AccountIds:
    Description: Comma separated list of account ids
    Type: CommaDelimitedList

Resources:

  SystemAdminPermissionSet:
    Type: AWS::SSO::PermissionSet
    Properties:
      InstanceArn: !Ref IamIdentityCenterInstanceArn
      Name: 'SystemAdmin'
      Description: 'System Admin Permissions'
      SessionDuration: 'PT8H'
      InlinePolicy:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Action: '*'
            Resource: '*'

  SystemAdminGroup:
    Type: AWS::IdentityStore::Group
    Properties:
      DisplayName: SystemAdmin
      Description: 'System Admin Group'
      IdentityStoreId: !Ref IdentityStoreId


  # Testing Account Assignments
  'Fn::ForEach::TestingAssignments':
    - AccountId
    - !Ref AccountIds
    - 'SystemAdminAssignment${AccountId}':
        Type: 'AWS::SSO::Assignment'
        Properties:
          InstanceArn: !Ref IamIdentityCenterInstanceArn
          PermissionSetArn: !GetAtt SystemAdminPermissionSet.PermissionSetArn
          TargetId: !Ref AccountId
          TargetType: AWS_ACCOUNT
          PrincipalId: !GetAtt SystemAdminGroup.GroupId
          PrincipalType: GROUP

```

Note:

I was able to bypass this by using:

```yaml
  'Fn::ForEach::TestingAssignments':
    - AccountId
    - !Ref AccountIds
    - 'SystemAdminAssignment${AccountId}':
        Type: 'AWS::SSO::Assignment'
        Metadata:
          cfn-lint:
            config:
              ignore_checks:
                - E3031
        Properties:
          InstanceArn: !Ref IamIdentityCenterInstanceArn
          PermissionSetArn: !GetAtt SystemAdminPermissionSet.PermissionSetArn
          TargetId: !Ref AccountId
          TargetType: AWS_ACCOUNT
          PrincipalId: !GetAtt SystemAdminGroup.GroupId
          PrincipalType: GROUP
```

This will work for now but ideally, I would like to be able to pass values for the parameters to be used for the linting.

### Additional contract requirements

- When a `Fn::ForEach` collection references a `CommaDelimitedList` parameter, each iteration must represent the corresponding parameter element in generated resources. Linting must not report a pattern-validation error solely because that element is parameterized and its concrete value is unavailable. If an element is concretely available and violates an applicable pattern, linting must still report the pattern-validation error.
