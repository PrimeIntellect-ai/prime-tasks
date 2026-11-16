Cannot catch "Fn::Equals object requires a list of 2 string parameters"
*cfn-lint version: (`cfn-lint --version`)*
```
cfn-lint 0.34.1
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
  Environments:
    Type: CommaDelimitedList
    Default: dev,test
Conditions:
  TagEnvironments: !Not
  - !Equals
    - !Ref Environments  # missed !Join
    - ''
Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 172.16.0.0/24
      Tags: !If
      - TagEnvironments
      - - Key: Environments
          Value: !Join
          - ','
          - !Ref Environments
      - []
$ aws cloudformation deploy --stack-name test --template-file template.yml

An error occurred (ValidationError) when calling the CreateChangeSet operation: Template error: every Fn::Equals object requires a list of 2 string parameters.
$ aws cloudformation validate-template --template-body file://template.yml

An error occurred (ValidationError) when calling the ValidateTemplate operation: Template error: every Fn::Equals object requires a list of 2 string parameters.
$ cfn-lint template.yml
$ echo $?
0
```
