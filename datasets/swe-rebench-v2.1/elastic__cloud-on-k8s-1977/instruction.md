Fix cluster UUID race condition during bootstrap
There seem to be a race condition during cluster bootstrap.

When ES is started, but not yet bootstrapped, the http endpoint is available and responds with cluster UUID `_na_` (see first note in this [doc](https://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-state.html)). We use that to populate ES CRDs clusteruuid annotation which is used to check whether cluster is already bootstrapped. When we think it is bootstrapped, we don't set `initial_master_nodes` that is required for the cluster to really bootstrap:

```
master not discovered yet, this node has not previously joined a bootstrapped (v7+) cluster, and [cluster.initial_master_nodes] is empty on this node
```

 This leaves the cluster in permanently broken state.

When deciding whether the cluster is bootstrapped we should also check if uuid is not `_na_`.
