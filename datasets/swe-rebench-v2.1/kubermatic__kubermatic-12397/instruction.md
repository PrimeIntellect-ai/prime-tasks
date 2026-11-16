etcd anti-affinity modes - Test Release 2.23
#12313 has added a new field to `.spec.componentOverrides.etcd` called `zoneAntiAffinity` which allows to fine-tune the anti-affinity behaviour used by the etcd `StatefulSet`. This ticket is to test it.

## How to Test

1. Create a user cluster on QA.
2. Edit the `Cluster` to update the component override for `zoneAntiAffinity`. Possible values are empty string, `preferred` (same as empty; this is the default behaviour) and `required`.
3. Check if the etcd StatefulSet reflects the different kinds of anti-affinity.
4. Make sure that for `required`, etcd Pods are distributed across different nodes and that not two of them run on the same node. They might be stuck in Pending if no nodes are available.
