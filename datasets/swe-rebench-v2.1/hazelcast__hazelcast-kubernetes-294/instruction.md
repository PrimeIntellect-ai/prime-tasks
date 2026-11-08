Hazelcast Kubernetes tries to access serviceaccount-token even if DNS Lookup is chosen method
https://github.com/hazelcast/hazelcast-kubernetes/blob/master/src/main/java/com/hazelcast/kubernetes/HazelcastKubernetesDiscoveryStrategy.java[HIDDEN]

On this line [HIDDEN], even if DNS_LOOKUP is chosen as discovery strategy.
This results in an attempt to access `/var/run/secrets/kubernetes.io/serviceaccount/token` which while fail in environments where token does not get auto-mounted for security reasons.

### Additional contract requirements

- In DNS_LOOKUP mode, `config.getKubernetesApiToken()` and `config.getKubernetesCaCertificate()` must return `null`.
- In DNS_LOOKUP mode, discovery must not attempt to access `/var/run/secrets/kubernetes.io/serviceaccount/token`.
