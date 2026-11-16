Add flag to enable cluster anti-affinity
Inter-pod [anti-affinity](https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#inter-pod-affinity-and-anti-affinity-beta-feature) is a great way to ensure like pods are scheduled on different nodes/failure domains. While it's useful, it also requires "substantial amount of processing which can slow down scheduling in large clusters significantly", so enabling it by default may not be desirable for many users.

We achieve a hacky version of anti-affinity by reserving enough memory for an m3db cluster such that it takes > 50% of a host's memory and no 2 m3db nodes will be scheduled on the same host. Some users may wish to use anti-affinity instead and we should enable that use case for them.

### Additional contract requirements

- Each isolation group exposes an opt-in boolean configuration field named `UsePodAntiAffinity`; anti-affinity is disabled unless that option is enabled.
- Each isolation group exposes a configuration field named `PodAffinityToplogyKey`. Its value selects the node-label topology key that defines the failure domain.
- When enabled, M3DB node pods must be required not to share the configured failure domain with other M3DB node pods.
