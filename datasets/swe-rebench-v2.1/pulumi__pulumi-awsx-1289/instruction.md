Misleading error message for invalid ECS task memory configuration
### What happened?

I just bumped the memory for the two containers of my `FargateService` task from 4GiB + 12GiB to 8GiB + 32GiB. When attempting to deploy this new configuration, I get the following error:

```
    aws:ecs:TaskDefinition (my-service-prod):
      error: 1 error occurred:
      	* failed creating ECS Task Definition (my-service-prod-718b5d41): ClientException: The 'memory' setting for container 'worker' is greater than for the task.
```

I could specify the exact memory for the task, but the docstring for `taskDefinitionArgs.memory` says "If not provided, a default will be computed based on the cumulative needs specified by [containerDefinitions]", so this seems like a bug

This seems very similar to #188

### Example

```
const service = new awsx.ecs.FargateService(`my-service-${stack}`, {
  cluster: cluster.arn,
  assignPublicIp: true,
  desiredCount: 2,
  deploymentMinimumHealthyPercent: 100,
  deploymentMaximumPercent: 200,
  taskDefinitionArgs: {
    taskRole: {
      roleArn: role.arn,
    },
    containers: {
      server: {
        command: ['yarn', 'server'],
        image: image.imageUri,
        cpu: 1024,
        memory: 1024 * 8,
        essential: true,
      },
      worker: {
        command: ['yarn', 'worker'],
        image: image.imageUri,
        cpu: 3072,
        memory: 1024 * 32,
        essential: true,
      },
    },
  },
});
```

### Output of `pulumi about`

```
CLI
Version      3.105.0
Go Version   go1.21.6
Go Compiler  gc

Plugins
NAME        VERSION
aws         5.33.0
awsx        1.0.2
cloudflare  5.0.0
docker      3.6.1
nodejs      unknown
tls         4.10.0

Host
OS       darwin
Version  14.2.1
Arch     arm64

This project is written in nodejs: executable='/Users/rpmccarter/.nvm/versions/node/v20.10.0/bin/node' version='v20.10.0'

Current Stack: Mintlify/leaves/staging

... (can send if needed, but would prefer to keep private)

Dependencies:
NAME                VERSION
@pulumi/aws         5.33.0
@pulumi/awsx        1.0.2
@pulumi/cloudflare  5.0.0
@pulumi/pulumi      3.60.0
@pulumi/tls         4.10.0
@types/node         16.18.22
rimraf              5.0.5
typescript          5.3.3

Pulumi locates its logs in /var/folders/dn/z0by0dcj1gnbkjr6_t71hp_m0000gn/T/ by default
```

### Contributing

Vote on this issue by adding a 👍 reaction.
To contribute a fix for this issue, leave a comment (and link to your pull request, if you've opened one already).

### Additional contract requirements

When task CPU and memory are inferred from container definitions, the selected task allocation must accommodate their cumulative resource requests and must not leave any container request above the task allocation. Requests at the supported Fargate CPU and memory maxima must be accepted. If either cumulative request exceeds its supported maximum, the request must be rejected rather than silently capped into an undersized task allocation.
