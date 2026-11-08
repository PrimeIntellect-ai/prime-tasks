cfn-lint cannot catch "Every Type member must be a string"
*cfn-lint version: (`cfn-lint --version`)*
```
cfn-lint 0.34.0
```

*aws-cli version: (`aws --version`)*
```
aws-cli/1.18.97 Python/3.8.3 Linux/4.15.0-111-generic botocore/1.16.26
```

*Description of issue.*
```
$ cat template.yml
AWSTemplateFormatVersion: 2010-09-09
Parameters:
  CloudformationType:
    Type: String
    Default: AWS::EC2::Instance
    AllowedValues:
    - AWS::EC2::Instance
    - AWS::AutoScaling::LaunchConfiguration
Resources:
  EC2InstanceOrLaunchConfig:
    Type: !Ref CloudformationType
    Properties:
      InstanceType: t3.nano
      ImageId: ami-0b90a8636b6f955c1
$ aws cloudformation deploy --stack-name test --template-file template.yml
An error occurred (ValidationError) when calling the CreateChangeSet operation: Template format error: [/Resources/EC2InstanceOrLaunchConfig] Every Type member must be a string.
$ aws cloudformation validate-template --template-body file://template.yml

An error occurred (ValidationError) when calling the ValidateTemplate operation: Template format error: [/Resources/EC2InstanceOrLaunchConfig] Every Type member must be a string.
$ cfn-lint template.yml
$ echo $?
0
```
