Support `removalPolicy` for stateful resources
## Hello!
<!-- Please leave this section as-is, it's designed to help others in the community know how to interact with our GitHub issues. -->

- Vote on this issue by adding a 👍 reaction
- If you want to implement this feature, comment to let us know (we'll work with you on design, scheduling, etc.)

## Issue details

<!-- Enhancement requests are most helpful when they describe the problem you're having as well as articulating the potential solution you'd like to see built. -->

Many stateful resources in the AWS Construct Library accept a `removalPolicy` as a property, typically defaulting it to `RETAIN`.

If the AWS Construct Library resource does not accept a removalPolicy argument, users can configure it by using the escape hatch mechanism, as shown in the following example:
```
cfn_bucket = bucket.node.find_child("Resource")
cfn_bucket.apply_removal_policy(RemovalPolicy.DESTROY)
```

Right now pulumi-cdk doesn't respect the removal policy and always deletes the resources.

### Affected area/feature

<!-- If you know the specific area where this feature request would go (e.g. Automation API, the Pulumi Service, the Terraform bridge, etc.), feel free to put that area here.  -->

### Additional contract requirements

The removal policy of a resource is reflected in the resource's Pulumi `retainOnDelete` option:

- `Delete` => `false`
- `Retain` => `true`
- `RetainExceptOnCreate` => `true`
- `Snapshot` => `true` (the resource is retained, since Pulumi cannot take a snapshot)
- when no removal policy is specified, the resource is not retained
