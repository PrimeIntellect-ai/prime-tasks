K8SSAND-1203 ⁃ Expose AllowMultipleWorkersPerNode from CassandraDatacenter spec
<!--

Feel free to ask questions on Discord at https://discord.com/invite/y4s64xC9 or in the forum at https://forum.k8ssandra.io/.
-->

**What is missing?**
The `AllowMultipleWorkersPerNode` allows multiple C* pods to be co-located on the same k8s worker node.

**Why do we need it?**
There are times during dev/testing when it is convenient to be able to co-locate C* pods particularly if there are a limited number of worker nodes. Some folks may use this for production deployments as well.

**Environment**

* K8ssandra Operator version:

    `Insert image tag or Git SHA here`
    <!-- Try kubectl describe deployment k8ssandra-operator -->
    <!-- Note: please provide operator version and not a helm chart version -->**Anything else we need to know?**:



┆Issue is synchronized with this [Jira Task](https://k8ssandra.atlassian.net/browse/K8SSAND-1203) by [Unito](https://www.unito.io)
┆friendlyId: K8SSAND-1203
┆priority: Medium

### Additional contract requirements

The cluster and datacenter templates expose this option as `softPodAntiAffinity`. When set to `true`, the resulting Cassandra datacenter permits multiple Cassandra pods to be scheduled on the same worker node.
