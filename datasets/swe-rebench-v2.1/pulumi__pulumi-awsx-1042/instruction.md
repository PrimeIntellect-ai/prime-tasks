Fargate max CPU size limits are no longer accurate
### What happened?

Fargate has increased the number of allowed vCPUs to 16: https://aws.amazon.com/about-aws/whats-new/2022/09/aws-fargate-increases-compute-memory-resource-configurations-4x/

In our vCPU calculation, we still have a ceiling of 4: https://github.com/pulumi/pulumi-awsx/blob/d03fbad7d367599aff8cffa9aff367dfd0fd6867/awsx/ecs/fargateMemoryAndCpu.ts#L66



### Expected Behavior

When setting the vCPU size of each container, we should allow a total of 16 vCPU

### Steps to reproduce

Create a task definition with multiple containers that has a vCPU requested of > 4

### Output of `pulumi about`

not required

### Additional context

_No response_

### Contributing

Vote on this issue by adding a 👍 reaction.
To contribute a fix for this issue, leave a comment (and link to your pull request, if you've opened one already).
