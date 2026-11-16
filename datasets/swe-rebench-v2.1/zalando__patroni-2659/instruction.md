Feature request: make value of replication role labels configurable
**Describe the feature**
Currently, on K8s the value of the labels that identify the replication role of each patroni/postgresql Pod is hardcoded to be "master" for the leader and "replica" for the followers.

I would like to make those values configurable.

That allows us to stop using the non-inclusive "master" term and replace it with something like "leader" or primary.

I would also like to opt out from using "replica". The reason is that I'm running patroni/spilo in a context where "replica" is already widely used to describe something different than postgresql's replication replicas. So currently there's a name overloading that causes confusion.

### Additional contract requirements

The values written into the Kubernetes role label (the label named by the existing `role_label` option, which defaults to `role`) are read from the Kubernetes DCS configuration mapping passed to `Kubernetes`:

- `leader_label_value`: value of the role label when the node is the leader. Default `master`.
- `follower_label_value`: value of the role label when the node is a replica. Default `replica`.
