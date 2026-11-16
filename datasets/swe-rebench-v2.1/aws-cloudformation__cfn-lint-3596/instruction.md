W4001 doesnt warn
### CloudFormation Lint Version

v1.10.1

### What operating system are you using?

windows

### Describe the bug

Metadata AWS::CloudFormation::Interface parameters do not warn when a parameter does not exist. Confirmed it works in v0.87.10. I've noticed this bug in other v1.x releases too.

### Expected behavior

warn when a interface metadata parameter exists but is not a parameter

### Reproduction template

```
AWSTemplateFormatVersion: 2010-09-09

Metadata:
  AWS::CloudFormation::Interface:
    ParameterGroups:
      - Label:
          default: 'Vpc Parameters'
        Parameters:
          - Vpc

Parameters:
  # Vpc Parameters
  VpcId:
    Description: VPC To Create Stack In
    Type: String

Resources:
  Test:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref VpcId
```

### Additional contract requirements

- The warning is reported with rule id `W4001`.


- For the invalid parameter in the reproduction template, report W4001 at `Metadata/AWS::CloudFormation::Interface/ParameterGroups/0/Parameters/0` (line 9, columns 13–16), with the message `"'Vpc' is not one of ['VpcId']"`.
