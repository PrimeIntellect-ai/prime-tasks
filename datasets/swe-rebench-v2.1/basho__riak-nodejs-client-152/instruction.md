Support load balancers [JIRA: CLIENTS-829]
`RiakNode` should take an option indicating that it is really a load balancer and not a Riak node. If this option is set, then the node will never be marked offline.

### Additional contract requirements

Set this option through the public `RiakNode.Builder.withExternalLoadBalancer` method.
