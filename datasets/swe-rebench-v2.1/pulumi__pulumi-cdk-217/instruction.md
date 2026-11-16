AWS CCAPI resources should be invoked from the SDK
### What happened?

When we create `aws-native` resources via the mapping, we use a `pulumi.CustomResource` instead of the appropriate class from the aws-native sdk.

https://github.com/pulumi/pulumi-cdk/blob/5912f830788319b8e9b66f6b1c9922baa6b4d454/src/interop.ts?plain=1#L87

This means that we don't get any of the generated sdk stuff like `replaceOnChanges`.

### Example

Deploy the `examples/fargate` example and then change the taskDefinition image. The TaskDefinition should be replaced because `containerDefinitions` is `replaceOnChange`.

### Output of `pulumi about`

n/a

### Additional context

_No response_

### Contributing

Vote on this issue by adding a 👍 reaction.
To contribute a fix for this issue, leave a comment (and link to your pull request, if you've opened one already).

### Additional contract requirements

- The mapping entry point is `mapToCfnResource(logicalId: string, cfnType: string, cfnProps: any, options: pulumi.ResourceOptions)` in `src/cfn-resource-mappings.ts`. Given a CloudFormation type token such as `AWS::ECS::TaskDefinition`, it constructs and returns the corresponding `@pulumi/aws-native` resource class (for example `aws.ecs.TaskDefinition`), forwarding the resource properties.
