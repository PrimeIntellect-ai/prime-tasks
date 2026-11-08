Root volume type 'standard' is no longer accepted since kops 1.19
**1. What `kops` version are you running? The command `kops version`, will display
 this information.**

Version 1.19.0-alpha.5 (git-921f3e7109a4871ec1cb0b0e512785533a24dbce)

**2. What Kubernetes version are you running? `kubectl version` will print the
 version if a cluster is running or provide the Kubernetes version specified as
 a `kops` flag.**

1.19.3 but should be reproducible with any version

**3. What cloud provider are you using?**

AWS

**4. What commands did you run?  What is the simplest way to reproduce this issue?**

Use a template with values

```
  etcdClusters:
  - etcdMembers:
      volumeType: standard
```

then create or update a cluster

**5. What happened after the commands executed?**

spec.rootVolumeType: Unsupported value: "standard": supported values: "gp2", "io1"

**6. What did you expect to happen?**

Expected 'standard' to be supported as this value works in kops 1.18.x
The main issue for us is that we cannot upgrade our clusters created with 'standard' volumes if we change the spec to 'gp2':

error: error replacing cluster: [spec.etcdClusters[main].etcdMembers[etcd-eu-central-1a].volumeType: Forbidden: volumeType cannot be cha
nged, spec.etcdClusters[events].etcdMembers[etcd-eu-central-1a].volumeType: Forbidden: volumeType cannot be changed]

This is caused by https://github.com/kubernetes/kops/pull/9265 as it implements the validation but does not allow for 'standard' type

I should also mention that this issue was once fixed in https://github.com/kubernetes/kops/issues/4256
