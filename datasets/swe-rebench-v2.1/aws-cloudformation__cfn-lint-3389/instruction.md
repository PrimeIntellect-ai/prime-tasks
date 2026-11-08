v1: E3510 'arn:aws:medialive:*' does not match '^(arn:(aws|aws-cn|aws-us-gov):[^:]+:[^:]*:(?:\\d{12}|\\*|aws)?:.+|\\*)$'
### CloudFormation Lint Version

1.3.3

### What operating system are you using?

Ubuntu

### Describe the bug

The following policy document resource ARN fails to validate:

`Resource: "arn:aws:medialive:*"`

### Expected behavior

Validation should pass.

### Reproduction template

```yaml
AWSTemplateFormatVersion: "2010-09-09"
Resources:
  SomeManagedPolicy:
    Type: "AWS::IAM::ManagedPolicy"
    Properties:
      PolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Action:
              - medialive:BatchUpdateSchedule
              - medialive:DeleteSchedule
            Resource: "arn:aws:medialive:*"
```
