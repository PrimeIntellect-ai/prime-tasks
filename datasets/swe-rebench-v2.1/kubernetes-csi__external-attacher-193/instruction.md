Update external-attacher to use v1.CSINode
We can also remove the fallback on Node annotation at the same time. This change will require a major version bump because we would have to bump the min K8s version to 1.17 when the object was introduced.

We should make this change at least 1, if not 2 releases before the v1beta gets removed from Kubernetes.

/lifecycle frozen

### Additional contract requirements

- The CSINode lister accepted by `NewCSIHandler` in package `pkg/controller` must be a `storage/v1` CSINode lister (`storagelisters.CSINodeLister` from `k8s.io/client-go/listers/storage/v1`), replacing the previous `storage/v1beta1` lister.
- `GetNodeIDFromCSINode(driver string, csiNode *storage.CSINode) (string, bool)` in package `pkg/controller` must accept a `storage/v1` `CSINode` (`k8s.io/api/storage/v1`) and return the node ID registered for the named driver together with whether such a driver entry was found.
