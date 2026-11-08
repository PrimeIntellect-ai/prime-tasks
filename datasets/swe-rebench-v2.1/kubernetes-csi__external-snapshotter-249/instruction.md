Cannot delete VolumeSnapshotContent with 'Retain' policy for imported snapshot using external-snapshotter beta
**Kubernetes version:**
```
Client Version: version.Info{Major:"1", Minor:"17", GitVersion:"v1.17.2", GitCommit:"59603c6e503c87169aea6106f57b9f242f64df89", GitTreeState:"clean", BuildDate:"2020-01-18T23:30:10Z", GoVersion:"go1.13.5", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"17+", GitVersion:"v1.17.0-gke.5", GitCommit:"ef996ac10bf4abe5cff462781fe9508d7468b657", GitTreeState:"clean", BuildDate:"2020-01-30T19:02:11Z", GoVersion:"go1.13.4b4", Compiler:"gc", Platform:"linux/amd64"}
```

**Snapshot common controller image:**
```
quay.io/k8scsi/snapshot-controller:v2.0.0
```

**snapshot sidercar controller image:**
```
quay.io/k8scsi/csi-snapshotter:v2.0.0
```

**Reproduce steps:**
1. Create VolumeSnapshotContent with snapshot handle, the DeletionPolicy is **Retain**:
```
Name:         snapshotcontent-static-binding
Namespace:
Labels:       <none>
Annotations:  kubectl.kubernetes.io/last-applied-configuration:
                {"apiVersion":"snapshot.storage.k8s.io/v1beta1","kind":"VolumeSnapshotContent","metadata":{"annotations":{},"name":"snapshotcontent-static...
API Version:  snapshot.storage.k8s.io/v1beta1
Kind:         VolumeSnapshotContent
Metadata:
  Creation Timestamp:  2020-02-07T01:13:49Z
  Generation:          1
  Resource Version:    967234
  Self Link:           /apis/snapshot.storage.k8s.io/v1beta1/volumesnapshotcontents/snapshotcontent-static-binding
  UID:                 8e2e5e8b-005d-4719-8397-a1527c5da009
Spec:
  Deletion Policy:  Retain
  Driver:           pd.csi.storage.gke.io
  Source:
    Snapshot Handle:  <handle>
  Volume Snapshot Ref:
    Name:       snapshot-static-binding
    Namespace:  default
Status:
  Creation Time:    1580448624526000000
  Ready To Use:     true
  Restore Size:     5368709120
  Snapshot Handle:  <handle>
Events:             <none>
```

2. Create VolumeSnapshot bound to content:
```
Name:         snapshot-static-binding
Namespace:    default
Labels:       <none>
Annotations:  kubectl.kubernetes.io/last-applied-configuration:
                {"apiVersion":"snapshot.storage.k8s.io/v1beta1","kind":"VolumeSnapshot","metadata":{"annotations":{},"name":"snapshot-static-binding","nam...
API Version:  snapshot.storage.k8s.io/v1beta1
Kind:         VolumeSnapshot
Metadata:
  Creation Timestamp:  2020-02-07T01:15:00Z
  Finalizers:
    snapshot.storage.kubernetes.io/volumesnapshot-as-source-protection
  Generation:        1
  Resource Version:  967584
  Self Link:         /apis/snapshot.storage.k8s.io/v1beta1/namespaces/default/volumesnapshots/snapshot-static-binding
  UID:               c06ceffa-0581-4c94-9a8d-c8458d526209
Spec:
  Source:
    Volume Snapshot Content Name:  snapshotcontent-static-binding
Status:
  Bound Volume Snapshot Content Name:  snapshotcontent-static-binding
  Creation Time:                       2020-01-31T05:30:24Z
  Ready To Use:                        true
  Restore Size:                        5Gi
Events:                                <none>
```

3. Delete VolumeSnapshot, and it is gone successfully.
4. Delete VolumeSnapshotContent, the finalizer is never removed from content:
```
Name:         snapshotcontent-static-binding
Namespace:
Labels:       <none>
Annotations:  kubectl.kubernetes.io/last-applied-configuration:
                {"apiVersion":"snapshot.storage.k8s.io/v1beta1","kind":"VolumeSnapshotContent","metadata":{"annotations":{},"name":"snapshotcontent-static...
API Version:  snapshot.storage.k8s.io/v1beta1
Kind:         VolumeSnapshotContent
Metadata:
  Creation Timestamp:             2020-02-07T01:13:49Z
  Deletion Grace Period Seconds:  0
  Deletion Timestamp:             2020-02-07T01:16:27Z
  Finalizers:
    snapshot.storage.kubernetes.io/volumesnapshotcontent-bound-protection
  Generation:        3
  Resource Version:  968001
  Self Link:         /apis/snapshot.storage.k8s.io/v1beta1/volumesnapshotcontents/snapshotcontent-static-binding
  UID:               8e2e5e8b-005d-4719-8397-a1527c5da009
Spec:
  Deletion Policy:  Retain
  Driver:           pd.csi.storage.gke.io
  Source:
    Snapshot Handle:  <handle>
  Volume Snapshot Ref:
    Name:       snapshot-static-binding
    Namespace:  default
    UID:        c06ceffa-0581-4c94-9a8d-c8458d526209
Status:
  Creation Time:    1580448624526000000
  Ready To Use:     true
  Restore Size:     5368709120
  Snapshot Handle:  <handle>
Events:             <none>
```

Finalizer **snapshot.storage.kubernetes.io/volumesnapshotcontent-bound-protection** on VolumeSnapshotContent is never gone.

### Additional contract requirements

When the common controller reconciles a VolumeSnapshot that is a deletion candidate (its deletion timestamp is set) and the snapshot is not in use, it must set the annotation `snapshot.storage.kubernetes.io/volumesnapshot-being-deleted` to the value `yes` on the associated VolumeSnapshotContent. Setting this annotation is what allows the retained VolumeSnapshotContent's bound-protection finalizer to be removed so the content can be deleted.
