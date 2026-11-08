Add support for topologySearchConstraints in Zookeeper helm charts
### Description

_Add support for [topologySpreadConstraints](https://kubernetes.io/docs/concepts/workloads/pods/pod-topology-spread-constraints/) in Zookeeper helm charts

### Importance

_should-have_

### Location

[_zookeeper.yaml_](https://github.com/pravega/zookeeper-operator/blob/master/charts/zookeeper/templates/zookeeper.yaml)

### Suggestions for an improvement

_Very similar to how support is provided for POD anti-affinity_

### Additional contract requirements

The topologySpreadConstraints support is exposed through the operator's Go API and rendered by the Helm chart:

- `PodPolicy` (in `api/v1beta1`) gains a field `TopologySpreadConstraints []v1.TopologySpreadConstraint` with JSON tag `topologySpreadConstraints`.
- `zk.MakeStatefulSet` copies `Spec.Pod.TopologySpreadConstraints` onto the generated StatefulSet pod spec's `TopologySpreadConstraints`. When the field is unset, the generated pod spec has no topology spread constraints.
- `PodPolicy.DeepCopy` and `ZookeeperCluster.DeepCopy` duplicate the `TopologySpreadConstraints` slice, preserving its length and contents, so that modifying the copy does not affect the original. A nil slice is copied as nil.
- The Helm chart exposes the setting through the `pod.topologySpreadConstraints` values key, which is rendered into the ZookeeperCluster CR's `spec.pod.topologySpreadConstraints`.
- The ZookeeperCluster CustomResourceDefinition schema must accept `topologySpreadConstraints` in the pod policy (`spec.pod`), so that the API server does not prune the field.
