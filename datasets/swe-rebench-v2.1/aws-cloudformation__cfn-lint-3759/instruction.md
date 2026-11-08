!GetAtt DocDB::Cluster.Port is reporting as an integer
              @kddejong after this change, it's not clear to me how we're supposed to Output for example an RDS DBCluster's Port, which is a number.

`Value: !GetAtt DBCluster.Port` fails with E6101
Attempting to cast it with something like `Value: !Sub ${DBCluster.Port}` also fails with E6101

Unless that is something that changed very recently, CloudFormation used to happily accept `Value: !GetAtt DBCluster.Port`

_Originally posted by @Dantemss in https://github.com/aws-cloudformation/cfn-lint/issues/3725#issuecomment-2419900363_

### Additional contract requirements

The resource in this report is an `AWS::DocDB::DBCluster` (not an `AWS::RDS::DBCluster`). Its `Port` attribute may be used directly as an Output value with `Fn::GetAtt`, or interpolated into an Output value with `Fn::Sub`, without E6101.
