Allow setting "None" in NAT Gateway Strategy for private subnets
There are valid situations whereby you'd want to create valid private subnets but not have NAT Gateways:

```
const vpc = new awsx.ec2.Vpc("natInstance", {
    numberOfAvailabilityZones: 2,
    cidrBlock: "172.20.0.0/22",
    natGateways: {
        strategy: "None"
    }
})
```

One such example is if you're deciding to use NAT instances for cost-effective egresss from a VPC
