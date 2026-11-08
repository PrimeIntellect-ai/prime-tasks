cf-lint throws an error on valid values for Elasticache Readenpoint address
### CloudFormation Lint Version

v1.11.0

### What operating system are you using?

Windows

### Describe the bug

Below is the yaml I am using for CLoudwatch alarm

Type: AWS::CloudWatch::Alarm
    DependsOn: ElasticacheRedis
    Properties:
      Dimensions:
        - Name: CacheClusterId
          Value: !Select [ 0, !Split [ "." , !Select [ 1, !Split [ "[", !Select [ 0, !Split [ " " , !GetAtt ElasticacheRedis.ReadEndPoint.Addresses ] ] ] ] ] ]


cfn-lint throws an error that
E1017 {'Fn::GetAtt': ['ElasticacheRedis', 'ReadEndPoint.Addresses']} is not of type 'string'

I am sure this was working a while back

Note: I have trimmed the content and just left the problematic line

### Expected behavior

There should not be any lint errors

### Reproduction template

Type: AWS::CloudWatch::Alarm
    DependsOn: ElasticacheRedis
    Properties:
      Dimensions:
        - Name: CacheClusterId
          Value: !Select [ 0, !Split [ "." , !Select [ 1, !Split [ "[", !Select [ 0, !Split [ " " , !GetAtt ElasticacheRedis.ReadEndPoint.Addresses ] ] ] ] ] ]

### Additional contract requirements

- The fix must be general rather than specific to ElastiCache: any `Fn::GetAtt`
  that resolves to an attribute whose schema type is an array must be treated as
  string-compatible. For example, `!GetAtt MySimpleAd.DnsIpAddresses` (an
  array-valued attribute of `AWS::DirectoryService::SimpleAD`) must not produce a
  type error when used where a string is expected, both directly in `Fn::GetAtt`
  and inside `Fn::Sub` (e.g. `${MySimpleAd.DnsIpAddresses}`).
