v1: false-positive for `E3024`
### CloudFormation Lint Version

cfn-lint 1.3.0

### What operating system are you using?

Windows 11

### Describe the bug

After updating from `v0.87.7` to `v1.3.0` i noticed a new finding, which is a false-positive:

```yaml
  SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: "Security Group"
      VpcId: !ImportValue VPC1-VPC-ID
      Tags:
        - Key: Name
          Value: 'SecurityGroup\'
```

```sh
[cfn-lint] E3024: 'SecurityGroup\\' does not match '^([\\p{L}\\p{Z}\\p{N}_.:/=+\\-@]*)$'
```

### Expected behavior

cfn-lint does not provide this false-positive finding. I think the regex might be wrong, but regex is not my speciality.

### Reproduction template

```yaml
AWSTemplateFormatVersion: 2010-09-09
Description: Test

Resources:
  SecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: "Security Group"
      VpcId: !ImportValue VPC1-VPC-ID
      Tags:
        - Key: Name
          Value: 'SecurityGroup\'
```

### Additional contract requirements

- For an array-form tag with key `aws:Foo`, the error message is exactly `'aws:Foo' does not match '^(?!aws:).+$'`; for an object-form `Tags` entry keyed `aws:Foo`, it is exactly `'aws:Foo' does not match any of the regexes: '^(?!aws:).+$'`.
