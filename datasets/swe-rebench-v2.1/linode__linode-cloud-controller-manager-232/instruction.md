🐛 Nodes added following initial LoadBalancer creation missing Shared IP with Cilium BGP LoadBalancing
## General:
When using Cilium BGP loadbalancing, nodes that join the cluster following the initial call to EnsureLoadBalancer are not getting the shared IP address applied.

* [X] Have you removed all sensitive information, including but not limited to access keys and passwords?
* [X] Have you checked to ensure there aren't other open or closed [Pull Requests](../../pulls) for the same bug/feature/question?

----

## Bug Reporting

### Expected Behavior
Applicable new nodes should get the shared IP assigned when they join the cluster if a cilium BGP Load Balancer exists.

### Actual Behavior
New nodes are not getting the shared IP assigned.

### Steps to Reproduce the Problem

  1. Deploy CCM with cilium BGP load balancing enabled
  1. Deploy a sample deployment such as nginx
  1. Create a service of type LoadBalancer to expose the sample deployment
  1. Scale up the cluster to add a new node
  1. Observe the new node does not get the shared IP attached to it in the Linode Cloud Manager.

### Environment Specifications

#### Screenshots, Code Blocks, and Logs

#### Additional Notes

----

For general help or discussion, join the [Kubernetes Slack team](https://kubernetes.slack.com/messages/CD4B15LUR/details/) channel `#linode`. To sign up, use the [Kubernetes Slack inviter](http://slack.kubernetes.io/).

The [Linode Community](https://www.linode.com/community/questions/) is a great place to get additional support.
