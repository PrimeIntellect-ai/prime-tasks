NFS mount options ignored by CSI in Volume Snapshot request
Hi all,
I have the following problem using the csi-driver-nfs driver in both v4.9.0 and v4.10.0 recently updated.

Both versions were installed with helm according to the instructions without specifying the externalSnapshotter option as it was giving an error:

   Error: INSTALLATION FAILED: Unable to continue with install: CustomResourceDefinition "volumesnapshots.snapshot.storage.k8s.io" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; annotation validation error: key "meta.helm.sh/release-name" must equal "csi-driver-nfs": current value is "rke2-snapshot-controller-crd"

I configured two different storage classes with the same driver, one that points to an nfs share exposed by a storage system without the need to specify mount options and a second instead towards a Qumulo storage system that requires the following mount options set (nolock, proto=tcp, vers=3).

I have no problem with both in their use and I correctly create PVCs on both and the PVs are correctly in boud and by accessing the share I find the content.

The real problem I have on the second Qumulo share with the mount options is in the use of the corresponding VolumeSnapshotClasses that allows me to backup the PVs via Rubrik, because it seems not to pass the mount options in particular the nolock.

Unfortunately on the Qumulo storage system it is not currently possible to disable it for general or single share configuration.

Here are some details:

  1) As as confirmed the csi-nfs-controller.log details:

   I0204 05:54:11.509884 1 utils.go:110] GRPC call: /csi.v1.Controller/CreateSnapshot
   I0204 05:54:11.510015 1 utils.go:111] GRPC request: {"name":"snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da","source_volume_id":"qumulo.opbg.dom#RancherPrimeTestSistemisti#pvc-2461ab54-6003-4a53-87fd-b83a6233f576##"}
   I0204 05:54:11.510110 1 controllerserver.go:496] internally mounting qumulo.opbg.dom:/RancherPrimeTestSistemisti at /tmp/snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da
   I0204 05:54:11.510191 1 nodeserver.go:132] NodePublishVolume: volumeID(qumulo.opbg.dom#RancherPrimeTestSistemisti#snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da#snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da#pvc-2461ab54-6003-4a53-87fd-b83a6233f576) source(qumulo.opbg.dom:/RancherPrimeTestSistemisti) targetPath(/tmp/snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da) mountflags([])
   I0204 05:54:11.510242 1 mount_linux.go:218] Mounting cmd (mount) with arguments (-t nfs qumulo.opbg.dom:/RancherPrimeTestSistemisti /tmp/snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da)
   E0204 05:54:17.885288 1 mount_linux.go:230] Mount failed: exit status 32
   Mounting command: mount
   Mounting arguments: -t nfs qumulo.opbg.dom:/RancherPrimeTestSistemisti /tmp/snapshot-4e132ac9-4201-4990-be4c-204b266f4bfb
   Output: mount.nfs: rpc.statd is not running but is required for remote locking.
   mount.nfs: Either use '-o nolock' to keep locks local, or start statd.
   mount.nfs: Protocol not supported

  2) Notably, line #4,#5 shows empty mount flags:

   I0204 05:54:11.510191 1 nodeserver.go:132] NodePublishVolume: volumeID(qumulo.opbg.dom#RancherPrimeTestSistemisti#snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da#snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da#pvc-2461ab54-6003-4a53-87fd-b83a6233f576) source(qumulo.opbg.dom:/RancherPrimeTestSistemisti) targetPath(/tmp/snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da) mountflags([])
   I0204 05:54:11.510242 1 mount_linux.go:218] Mounting cmd (mount) with arguments (-t nfs qumulo.opbg.dom:/RancherPrimeTestSistemisti /tmp/snapshot-70fc316a-e7e3-4cdd-9096-43188ba4b0da)

  3) The mount options are being ignored by the CSI. So seems like a defect with this CSI.

I kindly ask for support.

Thanks for your collaboration, Gabriele.
