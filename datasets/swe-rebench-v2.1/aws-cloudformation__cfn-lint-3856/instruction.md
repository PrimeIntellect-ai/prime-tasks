cfn-lint incorrectly issues `E1011` (`FindInMap` validation of configuration) with `!Sub` referencing `AWS::AccountId`
### CloudFormation Lint Version

1.20.1

### What operating system are you using?

Mac

### Describe the bug

cfn-lint incorrectly issues `E1011` (`FindInMap` validation of configuration) with `!Sub` referencing `AWS::AccountId`.

```
$ cfn-lint --format pretty --regions us-east-2 --include-checks I --configure-rule E3012:strict=True I3042:region=True I3042:accountId=True -- template.yaml

template.yaml
16:11:              E1011     '123456789012AccountBucketName' is not one of ['234567890123AccountBucketName'] for mapping 'BucketMap' and key 'BucketGroup'

Cfn-lint scanned 1 templates against 234 rules and found 1 errors, 0 warnings, and 0 informational violations
```

### Expected behavior

`E1011` is not issued for the reproduction template

### Reproduction template

```yaml
%YAML 1.2
---
AWSTemplateFormatVersion: 2010-09-09
Mappings:
  BucketMap:
    BucketGroup:
      234567890123AccountBucketName: Bucket
Transform: AWS::LanguageExtensions
Resources:
  Resource:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !FindInMap
        - BucketMap
        - BucketGroup
        - !Sub ${AWS::AccountId}AccountBucketName
```

### Additional contract requirements

- When the third argument of `Fn::FindInMap` is `Fn::Sub`, resolve the substitution against the selected mapping’s keys. A literal that matches a key resolves to that entry; substituting `Environment` resolves entries for each of its allowed values. A substitution involving `AWS::AccountId` that cannot match a key, and an invalid object-form substitution, produce no candidates.
- The public class `Context` in module `cfnlint.context.context` can be constructed with optional keyword arguments including `parameters`, `mappings`, and `resources`.
- The public class `Resource` in module `cfnlint.context.context` wraps a resource dictionary that contains at least a `Type` key and optional `Properties`.
