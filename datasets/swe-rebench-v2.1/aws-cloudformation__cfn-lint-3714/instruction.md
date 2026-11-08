[Bug] Rules support `Condition`, which is not a rule-specific intrinsic function
### CloudFormation Lint Version

1.15.0

### What operating system are you using?

Mac `pre-commit`

### Background

Note that I described similar behavior in #3630, which #3634 and #3703 attempted to address. Unfortunately it appears that these changes resulted in `cfn-lint` allowing the `Condition` function inside of rules, which is not an allowed [rule-specific intrinsic function](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/rules-section-structure.html#rules-specific-intrinsic-section-structure).

In particular, templates of the form described at https://github.com/aws-cloudformation/cfn-lint/issues/3630#issuecomment-2364176770 will throw:

```
Changeset creation failed. The reason was Template format error: Following functions are not supported in the Rules block of the template: [Condition].
```

### Describe the bug

The reproduction template throws:

```
W1001 Ref to resource 'InternetGateway' that may not be available when condition 'DeployGateway' is False and when condition 'DeployVpc' is True at Resources/InternetGatewayAttachment/Properties/InternetGatewayId
src/cloud-formation/indexer.cfn.yaml:32:7
```

Specifically, the purported hypothetical situation

> when condition 'DeployGateway' is False and when condition 'DeployVpc' is True

is impossible per the DeployVpc rule.

### Expected behavior

The lint should pass without template modification.

### Reproduction template

```yaml
---
Conditions:
  DeployGateway: !Equals
  - !Ref 'DeployGateway'
  - 'true'
  DeployVpc: !Equals
  - !Ref 'DeployVpc'
  - 'true'
Parameters:
  DeployAnything:
    AllowedValues:
    - 'false'
    - 'true'
    Type: 'String'
  DeployGateway:
    AllowedValues:
    - 'false'
    - 'true'
    Type: 'String'
  DeployVpc:
    AllowedValues:
    - 'false'
    - 'true'
    Type: 'String'
Resources:
  InternetGateway:
    Condition: 'DeployGateway'
    Type: 'AWS::EC2::InternetGateway'
  InternetGatewayAttachment:
    Condition: 'DeployVpc'
    Properties:
      InternetGatewayId: !Ref 'InternetGateway'
      VpcId: !Ref 'Vpc'
    Type: 'AWS::EC2::VPCGatewayAttachment'
  Vpc:
    Condition: 'DeployVpc'
    Properties:
      CidrBlock: '0.0.0.0/16'
    Type: 'AWS::EC2::VPC'
Rules:
  DeployGateway:
    Assertions:
    - Assert: !Or
      - !Equals
        - !Ref 'DeployAnything'
        - 'true'
      - !Equals
        - !Ref 'DeployGateway'
        - 'false'
  DeployVpc:
    Assertions:
    - Assert: !Or
      - !Equals
        - !Ref 'DeployGateway'
        - 'true'
      - !Equals
        - !Ref 'DeployVpc'
        - 'false'
...
```
