When nodes are cordoned they are not removed from the target group
I am running eks 1.14 and deployments with the ingress controller seem to work ok but when I drain a node or cordon a node it stays in the target group meaning its still routable via the ALB.

This has the effect that when running a load test and then draining a node I see 504
 errors when traffic is sent to the node and it is in the process of being terminated.

Is this the desired behaviour or a bug?

### Additional contract requirements

- When the controller resolves targets for an instance target group, a cordoned node must not be included in the resulting target set.
- When a node becomes cordoned, the controller must reconcile affected ingresses so their target sets are updated and that node is removed from the target group.
