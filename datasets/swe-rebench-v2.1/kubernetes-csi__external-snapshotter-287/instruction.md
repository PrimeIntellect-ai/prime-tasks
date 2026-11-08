VolumeSnapshot resources still remain after pass the E2E test
**What happened**:

Run storage E2E test and passed the test, but some VolumeSnapshot resources remain.

**What you expected to happen**:

VolumeSnapshot resources are deleted after E2E test.

**How to reproduce it (as minimally and precisely as possible)**:

Use https://github.com/zlabjp/kube-conformance .

Below is my testdriver.yaml

```
ShortName: ontap-block
StorageClass:
  FromName: false
  FromFile: </path/to/storage-class>
SnapshotClass:
  FromName: true
DriverInfo:
  Name: <Name My Storage Driver>
  Capabilities:
    persistence: true
    fsGroup: true
    exec: true
    block: true
    pvcDataSource: true
    controllerExpansion: true
    nodeExpansion: true
    volumeLimits: false
    singleNodeVolume: false
    snapshotDataSource: true
    topoligy: false
  SupportedSizeRange:
   Min: 1Gi
   Max: 10Gi
  RequiredAccessModes:
  - ReadWriteOnce
```

**Anything else we need to know?**:

The main cause may be [here](https://github.com/kubernetes-csi/external-snapshotter/blob/4b7aec33d4760138711058c8d94f324188b4e06b/pkg/common-controller/snapshot_controller_base.go#L217).

[HIDDEN]


On the E2E side, [here](https://github.com/kubernetes/kubernetes/blob/v1.17.3/test/e2e/storage/testsuites/provisioning.go#L669) is the logic to cleanup resources.

```
	cleanupFunc := func() {
		framework.Logf("deleting snapshot %q/%q", snapshot.GetNamespace(), snapshot.GetName())
		err = dynamicClient.Resource(snapshotGVR).Namespace(updatedClaim.Namespace).Delete(snapshot.GetName(), nil)
		if err != nil && !apierrs.IsNotFound(err) {
			framework.Failf("Error deleting snapshot %q. Error: %v", snapshot.GetName(), err)
		}

		framework.Logf("deleting initClaim %q/%q", updatedClaim.Namespace, updatedClaim.Name)
		err = client.CoreV1().PersistentVolumeClaims(updatedClaim.Namespace).Delete(updatedClaim.Name, nil)
		if err != nil && !apierrs.IsNotFound(err) {
			framework.Failf("Error deleting initClaim %q. Error: %v", updatedClaim.Name, err)
		}

		framework.Logf("deleting SnapshotClass %s", snapshotClass.GetName())
		framework.ExpectNoError(dynamicClient.Resource(snapshotClassGVR).Delete(snapshotClass.GetName(), nil))
	}
```

E2E doesn't wait for finishing to delete the VolumeSnapshot, and delete SnapshotClass.
So that, SnapshotResource can't be deleted.

[HIDDEN]

**Environment**:
- Kubernetes version (use `kubectl version`): v1.17.2
- Cloud provider or hardware configuration: openstack
- OS (e.g: `cat /etc/os-release`): container-linux-2303.3.0
- Kernel (e.g. `uname -a`): 4.19.86-coreos
- Install tools: original

### Additional contract requirements

A VolumeSnapshot must be able to finish deletion after its VolumeSnapshotClass has been deleted. An absent VolumeSnapshotClass must not by itself prevent attempting backend snapshot deletion or, after successful deletion, releasing protection on the associated content.
