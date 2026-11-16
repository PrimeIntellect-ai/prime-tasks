aws::ec2::networkinterface E1041 bug
### CloudFormation Lint Version

1.25.1

### What operating system are you using?

windows

### Describe the bug

[cfn-lint] E1041: {'Ref': 'EniSg'} does not match destination format of 'AWS::EC2::SecurityGroup.Id'


the custom function finds the SG Id and returns it for a !Ref in other resources. E1041 is picking it up as a format error

### Expected behavior

E1041 ignores the format error when a !Ref is to a Custom resource. I've confirmed that using a !Sub '${EniSg}' doesn't produce the error

### Reproduction template

```
Resources:
  EniSg:
    Type: Custom::SgFinder
    Properties:
      ServiceToken: test123
      SgIdentifier: Sg1

  Ec2NodeEni:
    Type: AWS::EC2::NetworkInterface
    Properties:
      Description: networkinterface
      GroupSet:
        - !Ref EniSg
      SubnetId: subnet-12345678
```
