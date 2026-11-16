False Positive for E3032
### CloudFormation Lint Version

cfn-lint 1.9.1

### What operating system are you using?

windows

### Describe the bug

error: [cfn-lint] E3032: [] is too short (1)

each member of the list its erroring on is conditionally created. there is a condition on the resource that is an OR of each conditional created member of the list. In the sample template below, the resource only gets created if atleast 1 of the deployment target OUs paramter for deployment is set to true. There was no error in v0.x


### Expected behavior

no error created. i have worked around the error by utilizing the resource metadata to ignore the rule

### Reproduction template

```
AWSTemplateFormatVersion: 2010-09-09

Parameters:
  Param1:
    Type: String
    Default: false
    AllowedValues:
      - false
      - true

  Param2:
    Type: String
    Default: false
    AllowedValues:
      - false
      - true

  Param3:
    Type: String
    Default: false
    AllowedValues:
      - false
      - true

Conditions:
  # Deployment Conditions
  ConditionValue1: !Equals [!Ref Param1, true]
  ConditionValue2: !Equals [!Ref Param2, true]
  ConditionValue3: !Equals [!Ref Param3, true]

  ConditionCreateStackSet: !Or
    - !Condition ConditionValue1
    - !Condition ConditionValue2
    - !Condition ConditionValue3

Resources:
  StackSet:
    #Metadata:
    #  cfn-lint:
    #    config:
    #      ignore_checks:
    #        - E3032 # Resource Doesnt Create if all Deployment OUs are false
    Type: AWS::CloudFormation::StackSet
    Condition: ConditionCreateStackSet
    Properties:
      AutoDeployment:
        Enabled: true
        RetainStacksOnAccountRemoval: true
      CallAs: SELF
      Description: 'Test123'
      ManagedExecution:
        Active: true
      OperationPreferences:
        FailureTolerancePercentage: 100
        MaxConcurrentPercentage: 100
        RegionConcurrencyType: PARALLEL
      PermissionModel: SERVICE_MANAGED
      StackInstancesGroup:
        - DeploymentTargets:
            OrganizationalUnitIds:
              - !If
                - ConditionValue1
                - ou-1234a-12345678
                - !Ref AWS::NoValue
              - !If
                - ConditionValue2
                - ou-1234b-12345678
                - !Ref AWS::NoValue
              - !If
                - ConditionValue3
                - ou-1234c-12345678
                - !Ref AWS::NoValue
          Regions:
            - !Ref AWS::Region
      StackSetName: 'test'
      TemplateBody: |
        AWSTemplateFormatVersion: '2010-09-09'

```
