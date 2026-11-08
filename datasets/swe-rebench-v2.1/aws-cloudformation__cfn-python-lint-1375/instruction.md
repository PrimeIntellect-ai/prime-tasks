E0002 during E3028: 'dict' object has no attribute 'get_safe'
*cfn-lint version: (0.28.1)*

```
> cfn-lint cloudformation_templates/lint_fail.yaml
E0002 Unknown exception while processing rule E3028: 'dict' object has no attribute 'get_safe'
cloudformation_templates/lint_fail.yaml:1:1
```

This did not occur on 0.27.4, which is what I was running before.

Here's the template:
```yaml
---
AWSTemplateFormatVersion: '2010-09-09'


Parameters:
  Serverless:
    Description: Whether to use Aurora Serverless
    Type: String
    AllowedValues: ["false", "true"]


Conditions:
  UseServerless: !Equals [!Ref Serverless, "true"]


Resources:
  AuroraCluster:
    Type: AWS::RDS::DBCluster
    Properties:
      Engine: aurora-postgresql
      EngineMode: !If [UseServerless, "serverless", "provisioned"]
      EngineVersion: "10.7"
      ScalingConfiguration: !If
        - UseServerless
        - AutoPause: true
          MaxCapacity: 192
          MinCapacity: 384
          SecondsUntilAutoPause: 1800
        - !Ref AWS::NoValue

```
