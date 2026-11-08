New Fargate Rules
*cfn-lint version: (`cfn-lint --version`)*: 0.32.1

*Description of issue.* New Rule Suggestions for ECS Fargate

Having just tried to deploy a new task alongside some existing tasks in Fargate, I ran across quite a few deployment failures that cfn-lint didn't warn me against, so this issue is simply a proposal for new rules to cover these cases.

- [x] ~~[Error] When an `AWS::ECS::Service` has its `LaunchType` set to `FARGATE`, it cannot have `SchedulingStrategy` set to `DAEMON`. Currently the only supported `SchedulingStrategy` is `REPLICA`. Reference: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_services.html#service_scheduler.~~ https://github.com/aws-cloudformation/cfn-lint/pull/2559
- [ ] [Error] When an `AWS::ECS::TaskDefinition` has its `NetworkMode` set to `awsvpc`, then any `AWS::ECS::TaskDefinition ContainerDefinition` subresources should either not specify any `HostPort` within each `PortMappings` entry, or should set it to equal the corresponding `ContainerPort`. Reference: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ecs-taskdefinition-containerdefinitions.html#cfn-ecs-taskdefinition-containerdefinition-portmappings.
- [ ] [Error] When an `AWS::ECS::TaskDefinition` has its `NetworkMode` set to `awsvpc`, its parent `AWS::ECS::Service` resource must specify a `NetworkConfiguration` (which should be of type `AWS::ECS::Service AwsVpcConfiguration`. Reference: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-service.html#cfn-ecs-service-networkconfiguration.
- [x] ~~[Error] Every `AWS::ECS::TaskDefinition` must contain at least one `AWS::ECS::TaskDefinition ContainerDefinition` that has `Essential` set to `true`. Reference: https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ecs-taskdefinition-containerdefinitions.html#cfn-ecs-taskdefinition-containerdefinition-essential.~~  https://github.com/aws-cloudformation/cfn-python-lint/pull/1548

### Additional contract requirements

- For an `AWS::ECS::TaskDefinition` whose `NetworkMode` is `awsvpc`, each `PortMappings` entry must omit `HostPort` or set it equal to that entry's `ContainerPort`.
- An `AWS::ECS::Service` that references a task definition whose `NetworkMode` is `awsvpc` must specify `NetworkConfiguration`.
- The service's `NetworkConfiguration`, when supplied, must conform to the `AWS::ECS::Service` network-configuration shape, including an `AwsvpcConfiguration` value of the `AwsVpcConfiguration` type.
