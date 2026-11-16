ecs task definition port mappings not applying all options
### What happened?

ecs task definitions are not applying most of the port mapping options, such as `name`, `appProtocol`, `containerPortRange`, and [some others](https://github.com/pulumi/pulumi-awsx/blob/master/awsx/schema-types.ts#L951).

### Example

setting port mappings like so on either an EC2 or Fargate task definition will result in an unnamed port definition being created, despite `name` being passed

```typescript
portMappings: [
  {
    name: 'my-port-name',
    containerPort: 80,
  },
],
```

this causes issues with service connect which **needs** port mappings to be named. this makes service connect unusable with pulumi.

### Output of `pulumi about`

CLI
Version      3.94.2
Go Version   go1.21.3
Go Compiler  gc

Host
OS       darwin
Version  14.0
Arch     arm64

### Additional context

_No response_

### Contributing

[HIDDEN]

### Additional contract requirements

- For both EC2 and Fargate task definitions, preserve every supported option supplied in each port mapping, including `name`, `appProtocol`, and `containerPortRange`. A supplied name must not be dropped, leaving the mapping unnamed.
