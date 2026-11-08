when ops is created, some key value such as namespace/name is better to validate if they are matched
In KuBeanClusterOps, there are some important keys between 4 yml files; such as:

1. In kubeanCluster.ymlm spec.hostsConfRef.namespace should be the same as metadata.namespace in hosts-conf-cm.yml
2. In kubeanCluster.ymlm spec.hostsConfRef.name should be the same as metadata.name in hosts-conf-cm.yml

### Additional contract requirements

In package `pkg/controllers/clusterops`, the `Controller` type exposes the following public methods:

- `CheckConfigMapExist(namespace string, name string) bool`: reports whether a ConfigMap with the given namespace and name exists. It returns false only when the ConfigMap is not found; any other error is treated as the ConfigMap existing, so the method returns true.
- `CheckSecretExist(namespace string, name string) bool`: reports whether a Secret with the given namespace and name exists. It returns false only when the Secret is not found; any other error is treated as the Secret existing, so the method returns true.
- `CheckClusterDataRef(cluster *kubeanclusterv1alpha1.KuBeanCluster, clusterOPS *kubeanclusteropsv1alpha1.KuBeanClusterOps) error`: validates the hosts configuration ConfigMap, the vars configuration ConfigMap and the SSH auth Secret referenced by the cluster. Each reference must exist and all referenced objects must reside in the same namespace. A nonempty reference on the KuBeanClusterOps overrides the corresponding reference on the KuBeanCluster; when the KuBeanClusterOps reference is empty, the KuBeanCluster reference is used. The method returns nil when the references are valid.

Existence is determined by querying the Kubernetes API through the controller's Kubernetes clientset (`ClientSet`).

The error returned by `CheckClusterDataRef` describes the first problem found and contains:

- `hostsConfRef is empty` when the hosts configuration reference is empty;
- `hostsConfRef <namespace>,<name> not found` when the referenced hosts configuration ConfigMap does not exist;
- `varsConfRef is empty` when the vars configuration reference is empty;
- `varsConfRef <namespace>,<name> not found` when the referenced vars configuration ConfigMap does not exist;
- `sshAuthRef <namespace>,<name> not found` when the referenced SSH auth Secret does not exist;
- `hostsConfRef varsConfRef or sshAuthRef not in the same namespace` when the referenced objects do not all reside in the same namespace.
