CAPV created resources should have the CAPI cluster-name label
/kind feature

**Describe the solution you'd like**
CAPI's topology controller guarantees that all resources realized by the controller pertaining to the cluster will have the `cluster.x-k8s.io/cluster-name` label. Any resources created by the providers might or might not follow the convention. CAPI does not define any label contract on these created resources.
To track the object to cluster association, CAPV should ensure any resource it creates can be tracked to a cluster object.

**Anything else you would like to add:**
A list of CAPV CRs to augment and verify:
- [ ] VSphereVM
- [x] IPAddressClaim

**Environment:**

- Cluster-api-provider-vsphere version:
- Kubernetes version: (use `kubectl version`):
- OS (e.g. from `/etc/os-release`):
