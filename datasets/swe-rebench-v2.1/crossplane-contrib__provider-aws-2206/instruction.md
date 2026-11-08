AWS EC2 Route Tables with Tags, never gets Ready
<!--
Thank you for helping to improve Crossplane!

Please be sure to search for open issues before raising a new one. We use issues
for bug reports and feature requests. Please find us at https://slack.crossplane.io/
for questions, support, and discussion.
-->

### What happened?
<!--
Please let us know what behaviour you expected and how Crossplane diverged from
that behaviour.
-->
After upgrading from version 0.49.2 to 0.52.0 we've detected that the EC2 RouteTable started updating non-stop.
We've been troubleshooting and debugging and it seems that the changes introduced in https://github.com/crossplane-contrib/provider-aws/commit/138b8cf25debbe75a98f5af919cb8e05b2850fd3 have changed the routetable.go code:
https://github.com/crossplane-contrib/provider-aws/blob/e02a4c2de22c21f188f5a514297b54e9bd7677cc/pkg/clients/ec2/routetable.go#L163

[HIDDEN]


### How can we reproduce it?
<!--
Help us to reproduce your bug as succinctly and precisely as possible. Artifacts
such as example manifests or a script that triggers the issue are highly
appreciated!
-->
Create a RouteTable CR in version 0.49.0 with a list of unordered tags, upgrade to 0.52.0 and the result with show itself.

### What environment did it happen in?
Crossplane version: 0.52.0
Cloud provider: AWS EKS 1.30

### Additional contract requirements

- A RouteTable must not require an update merely because its desired and current tags contain the same key/value pairs in a different order.
