Add support for Application Load Balancer to TargetGroup's valid types
Currently the valid TargetTypes include Instance, IP and Lambda.

ALB should also be added as a valid target group type - [ref](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-elasticloadbalancingv2-targetgroup.html#cfn-elasticloadbalancingv2-targetgroup-targettype).
