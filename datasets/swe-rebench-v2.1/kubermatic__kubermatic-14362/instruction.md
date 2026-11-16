Cloud Provider Openstack Support for LoadbalancerClasses in cloud.conf
### Description of the feature you would like to add / User story

<!-- We've provided an example format of the user story below. You're free to use any other format as well. -->

We would like to use the OpenStack Cloud Provider Controller Manager Feature for LoadbalancerClasses
in order to enable our users to choose between different floating ip pools easily.

### Solution details

<!-- Please, provide a bullet-pointed list or a few sentences of requirements that have to be met to mark the requested feature (user story) complete. -->

- Source code part that needs to be changed: https://github.com/kubermatic/kubermatic/blob/main/pkg/resources/cloudconfig/openstack/cloudconfig.go#L107
- Please refer to the official OpenStack CCM docs: https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/openstack-cloud-controller-manager/expose-applications-using-loadbalancer-type-service.md#switching-between-floating-subnets-by-using-preconfigured-classes
- We would like to specify a list of LoadbalancerClasses for different purposes: public, restricted-public, internal:
```
[LoadBalancerClass "public"]
floating-network-id="c57af0a0-da92-49be-a98a-345ceca004b3"
floating-subnet-id="f90d2440-d3c6-417a-a696-04e55eeb9279"

[LoadBalancerClass "restricted-public"]
floating-subnet-id="a374bed4-e920-4c40-b646-2d8927f7f67b"

[LoadBalancerClass "internal"]
floating-subnet-id="b374bed4-e920-4c40-b646-2d8927f7f67b"
```


fyi: @toschneck

### Additional contract requirements

- The OpenStack section of a datacenter specification accepts an optional `loadBalancerClasses` list. Each entry has a `name` and a `config` object. `config` accepts the optional string settings `floatingNetworkID` and `floatingSubnetID`, which name the floating network and floating subnet that load balancers of that class use for their floating IPs.
- Several named entries can be configured in the same datacenter, for example `public`, `restricted-public` and `internal`, and each entry keeps its own settings.
- The cloud.conf generated for clusters in that datacenter contains one `[LoadBalancerClass "<name>"]` section per configured entry. Each section carries that entry's `floating-network-id` and `floating-subnet-id` values, as in the example above.
