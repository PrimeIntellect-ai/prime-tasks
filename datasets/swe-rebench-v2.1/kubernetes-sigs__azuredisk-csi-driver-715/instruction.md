Dynamic Azure Disk PVC Extension causes pod to fail post resize
We are using a custom kubernetes cluster and we are using CSI driver for Dynamic Azure Disk provisioning. Normal Provisioning works without issues but trying to mount the PVC again post extension of the PVC gives the error. Please find the below steps taken and error reported.

**Steps for Creating CSI Driver in Kubernetes.**
1)kubectl create configmap azure-cred-file --from-literal=path="/etc/kubernetes/azure.json" -n kube-system
2) Using CSI version (0.9.0)
3)curl -skSL https://raw.githubusercontent.com/kubernetes-sigs/azuredisk-csi-driver/v0.9.0/deploy/install-driver.sh | bash -s v0.9.0 --
4)Content of Azure.json

 cat /etc/kubernetes/cloud.conf
{
    "cloud":"AzurePublicCloud",
    "tenantId": "xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "subscriptionId": "xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "aadClientId": "xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "aadClientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "resourceGroup": "xxxxxxxxxxxxx",
    "location": "",
    "subnetName": "",
    "securityGroupName": "",
    "vnetName": "",
    "vnetResourceGroup": "",
    "cloudProviderBackoff": true,
    "cloudProviderBackoffRetries": 6,
    "cloudProviderBackoffExponent": 1.5,
    "cloudProviderBackoffDuration": 5,
    "cloudProviderBackoffJitter": 1,
    "cloudProviderRatelimit": true,
    "cloudProviderRateLimitQPS": 3,
    "cloudProviderRateLimitBucket": 10,
    "useManagedIdentityExtension": false,
    "useInstanceMetadata": true
}

Error Logs:
**Normal Provision Working without Error**
root@master-testing:csi-azure-disk# kdesc sc managed-csi
Name:            managed-csi
IsDefaultClass:  No
Annotations:     kubectl.kubernetes.io/last-applied-configuration={"allowVolumeExpansion":true,"apiVersion":"storage.k8s.io/v1","kind":"StorageClass","metadata":{"annotations":{},"name":"managed-csi"},"parameters":{"skuname":"StandardSSD_LRS"},"provisioner":"disk.csi.azure.com","reclaimPolicy":"Delete","volumeBindingMode":"Immediate"}

Provisioner:           disk.csi.azure.com
Parameters:            skuname=StandardSSD_LRS
AllowVolumeExpansion:  True
MountOptions:          <none>
ReclaimPolicy:         Delete
VolumeBindingMode:     Immediate
Events:                <none>

root@master-testing:dynamic-azuredisk# kg pvc
NAME                                         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistent-storage-statefulset-azuredisk-0   Bound    pvc-187d49ee-1eca-4712-80d7-11e71802d883   5Gi        RWO            managed-csi    17s
root@master-testing:dynamic-azuredisk# kg pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                                STORAGECLASS   REASON   AGE
pvc-187d49ee-1eca-4712-80d7-11e71802d883   5Gi        RWO            Delete           Bound    default/persistent-storage-statefulset-azuredisk-0   managed-csi             14s

root@master-testing:dynamic-azuredisk# kexec -it statefulset-azuredisk-0 -- df -h /mnt/azuredisk
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdc        4.9G   20M  4.9G   1% /mnt/azuredisk

**Starting the Process to Resize it**
root@master-testing:dynamic-azuredisk# kubectl get statefulsets
NAME                    READY   AGE
statefulset-azuredisk   1/1     2m21s
root@master-testing:dynamic-azuredisk# kubectl scale statefulsets statefulset-azuredisk --replicas=0
statefulset.apps/statefulset-azuredisk scaled
root@master-testing:dynamic-azuredisk# kubectl get statefulsets
NAME                    READY   AGE
statefulset-azuredisk   0/0     3m39s

root@master-testing:dynamic-azuredisk# kubectl patch pvc  persistent-storage-statefulset-azuredisk-0 --type merge --patch '{"spec": {"resources": {"requests": {"storage": "8Gi"}}}}'
persistentvolumeclaim/persistent-storage-statefulset-azuredisk-0 patched
root@master-testing:dynamic-azuredisk# kg pv
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                                STORAGECLASS   REASON   AGE
pvc-187d49ee-1eca-4712-80d7-11e71802d883   8Gi        RWO            Delete           Bound    default/persistent-storage-statefulset-azuredisk-0   managed-csi             5m24s

root@master-testing:dynamic-azuredisk# kdesc pvc persistent-storage-statefulset-azuredisk-0
Name:          persistent-storage-statefulset-azuredisk-0
Namespace:     default
StorageClass:  managed-csi
Status:        Bound
Volume:        pvc-187d49ee-1eca-4712-80d7-11e71802d883
Labels:        app=nginx
Annotations:   pv.kubernetes.io/bind-completed: yes
               pv.kubernetes.io/bound-by-controller: yes
               volume.beta.kubernetes.io/storage-class: managed-csi
               volume.beta.kubernetes.io/storage-provisioner: disk.csi.azure.com
Finalizers:    [kubernetes.io/pvc-protection]
Capacity:      5Gi
Access Modes:  RWO
VolumeMode:    Filesystem
Used By:       <none>
Conditions:
  Type                      Status  LastProbeTime                     LastTransitionTime                Reason  Message
  ----                      ------  -----------------                 ------------------                ------  -------
  FileSystemResizePending   True    Mon, 01 Jan 0001 00:00:00 +0000   Thu, 04 Feb 2021 13:38:22 +0000           Waiting for user to (re-)start a pod to finish file system resize of volume on node.
Events:
  Type     Reason                    Age    From                                                                    Message
  ----     ------                    ----   ----                                                                    -------
  Normal   ExternalProvisioning      6m10s  persistentvolume-controller                                             waiting for a volume to be created, either by external provisioner "disk.csi.azure.com" or manually created by system administrator
  Normal   Provisioning              6m10s  disk.csi.azure.com_master-testing_cd332bc2-c8d2-45e7-8431-17a613df23c0  External provisioner is provisioning volume for claim "default/persistent-storage-statefulset-azuredisk-0"
  Normal   ProvisioningSucceeded     6m1s   disk.csi.azure.com_master-testing_cd332bc2-c8d2-45e7-8431-17a613df23c0  Successfully provisioned volume pvc-187d49ee-1eca-4712-80d7-11e71802d883
  Normal   Resizing                  53s    external-resizer disk.csi.azure.com                                     External resizer is resizing volume pvc-187d49ee-1eca-4712-80d7-11e71802d883
  Warning  ExternalExpanding         53s    volume_expand                                                           Ignoring the PVC: didn't find a plugin capable of expanding the volume; waiting for an external controller to process this PVC.
  Normal   FileSystemResizeRequired  51s    external-resizer disk.csi.azure.com                                     Require file system resize of volume on node

root@master-testing:dynamic-azuredisk# kubectl scale statefulsets statefulset-azuredisk --replicas=1
statefulset.apps/statefulset-azuredisk scaled

root@master-testing:dynamic-azuredisk# kgp
NAME                      READY   STATUS              RESTARTS   AGE
statefulset-azuredisk-0   0/1     ContainerCreating   0          78s

root@master-testing:dynamic-azuredisk# kdesc pod statefulset-azuredisk-0 | tail -10
Node-Selectors:  kubernetes.io/os=linux
Tolerations:     node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                 node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type     Reason                  Age               From                     Message
  ----     ------                  ----              ----                     -------
  Normal   Scheduled               89s               default-scheduler        Successfully assigned default/statefulset-azuredisk-0 to master-testing
  Normal   SuccessfulAttachVolume  78s               attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-187d49ee-1eca-4712-80d7-11e71802d883"
  Warning  FailedMount             8s (x8 over 72s)  kubelet                  MountVolume.MountDevice failed while expanding volume for volume "pvc-187d49ee-1eca-4712-80d7-11e71802d883" : Expander.NodeExpand failed to expand the volume : rpc error: code = Internal desc = Could not get size of block volume at path /var/lib/kubelet/plugins/kubernetes.io/csi/pv/pvc-187d49ee-1eca-4712-80d7-11e71802d883/globalmount: error when getting size of block volume at path /var/lib/kubelet/plugins/kubernetes.io/csi/pv/pvc-187d49ee-1eca-4712-80d7-11e71802d883/globalmount: output: , err: exit status 1



**Environment**
root@master-testing:csi-azure-disk# cat /etc/lsb-release
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=18.04
DISTRIB_CODENAME=bionic
DISTRIB_DESCRIPTION="Ubuntu 18.04.5 LTS"

### Additional contract requirements

- `NodeExpandVolume` must determine the device path for the volume from the request's
  `VolumePath`. It must not use `StagingTargetPath` as the device path.
- When the device path cannot be determined from `VolumePath`, `NodeExpandVolume` must
  return a gRPC `NotFound` error.
