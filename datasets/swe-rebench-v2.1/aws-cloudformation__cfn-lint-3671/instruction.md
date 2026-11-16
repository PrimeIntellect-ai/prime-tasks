Feature Request: AWS::ECS::Service - Add check for `HealthCheckGracePeriodSeconds needs ALB/NLB`
### Is this feature request related to a new rule or cfn-lint capabilities?

_No response_

### Describe the feature you'd like to request

Currently cfn-lint is unable to see that if you add

```
HealthCheckGracePeriodSeconds
The period of time, in seconds, that the Amazon ECS service scheduler ignores unhealthy Elastic Load Balancing target health checks after a task has first started.
This is only used when your service is configured to use a load balancer.
If your service has a load balancer defined and you don't specify a health check grace period value, the default value of 0 is used.

If you do not use an Elastic Load Balancing, we recommend that you use the startPeriod in the task definition health check parameters.
For more information, see Health check.

If your service's tasks take a while to start and respond to Elastic Load Balancing health checks, you can specify a health check grace period of up to 2,147,483,647 seconds (about 69 years).
During that time, the Amazon ECS service scheduler ignores health check status.
This grace period can prevent the service scheduler from marking tasks as unhealthy and stopping them before they have time to come up.

Required: No

Type: Integer

Update requires: No interruption
```

to `AWS::ECS::Service`, it doesn't know that you need an ALB/NLB attached or the deployment will fail with the following error message:

```
Resource handler returned message:
"Invalid request provided: UpdateService error: Health check grace period is only valid for services configured to use load balancers
(Service: AmazonECS; Status Code: 400; Error Code: InvalidParameterException;
```

### Describe the solution you'd like

cfn-lint finds this error.

### Additional context

Example:

```yaml
  ECSService:
    Type: AWS::ECS::Service
    Properties:
      Cluster: !Ref ECSCluster
      TaskDefinition: !GetAtt ECSTaskDefinition.TaskDefinitionArn
      DesiredCount: 1
      LaunchType: FARGATE
      PropagateTags: SERVICE
      NetworkConfiguration:
        AwsvpcConfiguration:
          SecurityGroups:
            - !GetAtt ECSSecurityGroup.GroupId
          Subnets:
            - <subnet>
      EnableExecuteCommand: true
      HealthCheckGracePeriodSeconds: 36000
```

### Is this something that you'd be interested in working on?

- [ ] 👋 I may be able to implement this feature request

### Would this feature include a breaking change?

- [ ] ⚠️ This feature might incur a breaking change

### Additional contract requirements

For an `AWS::ECS::Service`, setting `HealthCheckGracePeriodSeconds` requires at least one configured entry in `LoadBalancers`. An absent `LoadBalancers` property or an empty list does not satisfy this requirement; a non-empty configured load-balancer list does.
