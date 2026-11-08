Use driver name from PV instead of from StorageClass to validate
In current implementation, [SetDefaultSnapshotClass](https://github.com/kubernetes-csi/external-snapshotter/blob/master/pkg/common-controller/snapshot_controller.go#L1189) relies on PVC's StorageClass to find the driver name. Instead its more appropriate to rely on PV's driver name as StorageClass can be updated after a volume has been provisioned.

Per discussion in https://github.com/kubernetes/kubernetes/issues/94312

### Additional contract requirements

- The common snapshot controller in `pkg/common-controller` must expose a method `pvDriverFromSnapshot(snapshot *crdv1.VolumeSnapshot) (string, error)`. Given a snapshot whose source is a PersistentVolumeClaim, it returns the CSI driver name recorded on the PersistentVolume bound to that claim. It returns an error when the claim or the bound volume cannot be resolved, and when the bound volume is not a CSI volume.


- When setting the default snapshot class for a snapshot whose PVC `claim1-5` cannot be found, the snapshot error message must be exactly `Failed to set default snapshot class with error failed to retrieve PVC claim1-5 from the lister: "persistentvolumeclaim \"claim1-5\" not found"`.
