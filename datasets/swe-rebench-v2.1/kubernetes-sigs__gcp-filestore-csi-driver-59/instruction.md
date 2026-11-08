Handle NodePublish in compliance with CSI spec
Reference: https://github.com/kubernetes/kubernetes/issues/75535

During NodePublish, kubernetes today creates the target path (for e.g. /var/lib/kubelet/pods/<POD ID>/volumes/kubernetes.io~csi/<VolumeID>/mount).
This behavior will go away in future kubernetes version, where k8s would only create the parent dir  /var/lib/kubelet/pods/<POD ID>/volumes/kubernetes.iocsi/<VolumeID>

It is the driver's responsibility to ensure the target path is created (and delete during node unpublish).
Update the current node publish code, to check for existence of the target path and create one if needed (for linux), before proceeding to mount call.
