!GetAtt reference lint error
Hello,

Getting validation error on `AWS::ElasticLoadBalancingV2::Listener` property `LoadBalancerArn` when the `LoadBalancerArn` is referenced using !GetAtt nested-stack-name.Outputs.LoadbalancerArn

`[cfn-lint] E3008:CloudFormation stack outputs need to be strings not lists at Resources/ApiGwNlbListener/Properties/LoadBalancerArn/Fn::GetAtt
`
