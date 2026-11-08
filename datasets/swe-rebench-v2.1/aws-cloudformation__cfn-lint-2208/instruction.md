Custom Rule not working for boolean values
*cfn-lint version: (`cfn-lint --version`)* 0.54.4

*Description of issue.* Attempting to create a custom rule to detect KMS keys that do not have auto rotate enabled. I discovered https://github.com/aws-cloudformation/cfn-lint/issues/2185 which covers the inability to react to absence of a value, but I'm just having issues with booleans. I'm able to trip the rules, so I know custom rules are registering, but I'm unable to get it to trip only against KMS Key resources who's EnableKeyRotation is false

Please provide as much information as possible:
* Template linting issues:
  * Please provide a CloudFormation sample that generated the issue.
  * If present, please add links to the (official) documentation for clarification.
  * Validate if the issue still exists with the latest version of `cfn-lint` and/or the latest Spec files
* Feature request:
  * Please provide argumentation about the missing feature. Context is key!
Example cfn
```
---
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  TestKey:
    Properties:
      EnableKeyRotation: false
      KeyPolicy:
        Statement:
        - Action: kms:*
          Effect: Allow
          Principal:
            AWS:
              Fn::Sub: arn:${AWS::Partition}:iam::${AWS::AccountId}:root
          Resource: "*"
          Sid: Enable key management, including IAM user permissions
        Version: '2012-10-17'
    Type: AWS::KMS::Key
```

rules file (showing different casings/quotings in case it's relevant)-
```
AWS::KMS::Key EnableKeyRotation == True ERROR "KMS keys should be configured to auto rotate"
AWS::KMS::Key EnableKeyRotation == true ERROR "KMS keys should be configured to auto rotate"
AWS::KMS::Key EnableKeyRotation == TRUE ERROR "KMS keys should be configured to auto rotate"
AWS::KMS::Key EnableKeyRotation == "True" ERROR "KMS keys should be configured to auto rotate"
AWS::KMS::Key EnableKeyRotation == "true" ERROR "KMS keys should be configured to auto rotate"
AWS::KMS::Key EnableKeyRotation == "TRUE" ERROR "KMS keys should be configured to auto rotate"
```

if I flip the rules to
```
AWS::KMS::Key EnableKeyRotation == false ERROR "KMS keys should be configured to auto rotate"
```
No change. But if I then flip the cfn template's EnableKeyRotation to `true` it is then flagged in violation

Cfn-lint uses the [CloudFormation Resource Specifications](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-resource-specification.html) as the base to do validation. These files are included as part of the application version. Please update to the latest version of `cfn-lint` or update the spec files manually (`cfn-lint -u`)

### Additional contract requirements

- When an equality custom rule comparison fails, its diagnostic message must contain `Must equal check failed`.
