E1011 '123456789012' is not one of [ ... ] for mapping 'AWSAccountsMap'
### CloudFormation Lint Version

1.12.1

### What operating system are you using?

Ubuntu

### Describe the bug

Validation fails when using `!Ref AWS::AccountId` as top level key with `FindInMap` unless `123456789012` is provided as a key in the referenced map:

`E1011 '123456789012' is not one of ['222222222222', '333333333333'] for mapping 'AWSAccountsMap'`

(You can also get `E8005` errors for the same basic reason.)

### Expected behavior

The top level key `123456789012` should not be required in the map in order for validation to pass.

### Reproduction template

```yaml
AWSTemplateFormatVersion: 2010-09-09
Mappings:
  AWSAccountsMap:
    "222222222222":
      SomeData: lorem
    "333333333333":
      SomeData: ipsum
Resources:
  Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !FindInMap [AWSAccountsMap, !Ref AWS::AccountId, SomeData]
```
