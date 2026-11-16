[Bug] AWS::ElasticLoadBalancingV2::TargetGroup - Additional properties are not allowed ('Matcher' was unexpected)
### CloudFormation Lint Version

cfn-lint 1.33.1

### What operating system are you using?

Ubuntu

### Describe the bug

After latest update, linting is returning false positives for `Matcher` on `AWS::ElasticLoadBalancingV2::TargetGroup`:

```
Files/CloudformationTemplates/accounts/network-admin/nlb-to-internal-account-nlb.yaml
111:7:              E3683     Additional properties are not allowed ('Matcher' was unexpected)

Files/CloudformationTemplates/accounts/transit/nlb-to-mission-account-nlb.yaml
160:7:              E3683     Additional properties are not allowed ('Matcher' was unexpected)
```

Docs: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-targetgroup.html

`Matcher` is a valid property.

### Expected behavior

I expected this to pass linting as it is valid

### Reproduction template

```yaml
  NLBTargetGroup:
    Type: AWS::ElasticLoadBalancingV2::TargetGroup
    Properties:
      Name: !Sub ${AccountStackAlias}-tg
      Port: 8443
      Protocol: TCP
      TargetType: ip
      VpcId:
        Fn::ImportValue: !Sub "${VpcStackNameParameter}-VpcId"
      HealthCheckProtocol: HTTPS
      HealthCheckPort: 8443
      HealthCheckPath: /
      HealthCheckIntervalSeconds: 30
      HealthCheckTimeoutSeconds: 10
      HealthyThresholdCount: 2
      UnhealthyThresholdCount: 3
      Matcher:
        HttpCode: "200-499"
```
