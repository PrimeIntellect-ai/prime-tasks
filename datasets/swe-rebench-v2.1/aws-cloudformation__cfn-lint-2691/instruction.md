E2506 prevents using SourceSecurityGroupId for non-vpc security groups
https://github.com/aws-cloudformation/cfn-lint/blob/4a7af2bd53a9ad1ccaba3a509437c53102ade522/src/cfnlint/rules/resources/ectwo/SecurityGroupIngress.py#L33-L40

I couldn't see any reason in the [cloudformation reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-security-group-rule-1.html#cfn-ec2-security-group-rule-sourcesecuritygroupid) that this wouldn't be valid, and I was able successfully create the following stack, where SecurityGroupB seems to be correctly restricted to traffic from SecurityGroupA. I _think_ that this rule is incorrect, unless I'm missing something

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  SecurityGroupA:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Group A
      SecurityGroupIngress:
        - FromPort: 80
          ToPort: 80
          IpProtocol: tcp
          CidrIp: 0.0.0.0/0

  SecurityGroupB:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Group B
      SecurityGroupIngress:
        - FromPort: 80
          ToPort: 80
          IpProtocol: tcp
          SourceSecurityGroupId:
            Fn::GetAtt:
              - SecurityGroupA
              - GroupId
```
