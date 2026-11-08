containerd/runc assets are still downloaded if skipInstall is true
/kind bug

**1. What `kops` version are you running? The command `kops version`, will display
 this information.**
1.26.4

**2. What Kubernetes version are you running? `kubectl version` will print the
 version if a cluster is running or provide the Kubernetes version specified as
 a `kops` flag.**
1.26.6

**3. What cloud provider are you using?**
AWS/Spotinst

**4. What commands did you run?  What is the simplest way to reproduce this issue?**
Have a cluster with `.spec.containerd.skipInstall = true`.

**5. What happened after the commands executed?**
The node logs indicate that containerd and runc assets are downloaded and extracted. They are never used.

**6. What did you expect to happen?**
For this to not happen

### Additional contract requirements

- The asset-skipping behaviour applies to the container runtime configured for the cluster. When the cluster's container runtime is containerd and `.spec.containerd.skipInstall` is true, the containerd and runc assets are omitted from the nodeup asset list.
