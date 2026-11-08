ImagePullSecrets field is not supported
CRD ZookeeperCluster don't support ImagePullSecrets, the mirror image of the private warehouse cannot be pulled up.

```
apiVersion: zookeeper.pravega.io/v1beta1
kind: ZookeeperCluster
metadata:
  name: zookeeper
  namespace: default
spec:
  # Add fields here
  replicas: 3
  image:
    repository: xxxxx:8080/xxxxx/zookeeper
    tag: 3.6.1
  persistence:
    accessModes: [ "ReadWriteOnce" ]
    storageClassName: "cbs"
    reclaimPolicy: Delete
    resources:
      requests:
        storage: 10Gi
```

### Additional contract requirements

- `PodPolicy` in package `pkg/apis/zookeeper/v1beta1` must expose a field `ImagePullSecrets []v1.LocalObjectReference`, where `v1` is `k8s.io/api/core/v1`.
- `(*PodPolicy).DeepCopyInto(out *PodPolicy)` must copy `ImagePullSecrets` into a newly allocated slice of the same length, so that the destination does not share the underlying array with the source.
- The ZookeeperCluster CRD schema must accept `imagePullSecrets` under the PodPolicy specification, as a list of local secret references.
- Configured image pull secret references must be available on the ServiceAccount used by the Zookeeper workload.
