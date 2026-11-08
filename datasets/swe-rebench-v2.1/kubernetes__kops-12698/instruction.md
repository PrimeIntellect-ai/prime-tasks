Rolling update panic
/kind bug

**1. What `kops` version are you running? The command `kops version`, will display
 this information.**
```
Version 1.21.0-beta.3 (git-03fc6a2601809f143499d16aaab12cd7c22d9eed)
```

**2. What Kubernetes version are you running? `kubectl version` will print the
 version if a cluster is running or provide the Kubernetes version specified as
 a `kops` flag.**
```
Client Version: version.Info{Major:"1", Minor:"19", GitVersion:"v1.19.9", GitCommit:"9dd794e454ac32d97cde41ae10be801ae98f75df", GitTreeState:"clean", BuildDate:"2021-03-18T01:09:28Z", GoVersion:"go1.15.8", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"21", GitVersion:"v1.21.1", GitCommit:"5e58841cce77d4bc13713ad2b91fa0d961e69192", GitTreeState:"clean", BuildDate:"2021-05-12T14:12:29Z", GoVersion:"go1.16.4", Compiler:"gc", Platform:"linux/arm64"}
```

**3. What cloud provider are you using?**
AWS

**4. What commands did you run?  What is the simplest way to reproduce this issue?**
`kops rolling-update cluster --name <my cluster> --yes`

**5. What happened after the commands executed?**
Works for a while then panics.

**6. What did you expect to happen?**
No panic.

**7. Please provide your cluster manifest. Execute
  `kops get --name my.example.com -o yaml` to display your cluster manifest.
  You may want to remove your cluster name and other sensitive information.**

```yaml
---
apiVersion: kops.k8s.io/v1alpha2
kind: Cluster
metadata:
  name: panic.example.com
spec:
  fileAssets:
  - content: |
      podNodeSelectorPluginConfig:
        clusterDefaultNodeSelector: "kubernetes.io/role=node"
    name: admission-controller-config.yaml
    roles:
    - Master
  - content: |
      apiVersion: audit.k8s.io/v1
      kind: Policy
      rules:
      - level: Metadata
    name: audit.yaml
    roles:
    - Master
  kubeAPIServer:
    admissionControlConfigFile: /srv/kubernetes/assets/admission-controller-config.yaml
    auditPolicyFile: /srv/kubernetes/assets/audit.yaml
  kubernetesVersion: 1.21.1
---
apiVersion: kops.k8s.io/v1alpha2
kind: InstanceGroup
metadata:
  labels:
    kops.k8s.io/cluster: panic.example.com
  name: apiserver-eu-west-1a
spec:
  image: 099720109477/ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-20210415
  machineType: t4g.large
  maxSize: 1
  minSize: 1
  role: APIServer
  rollingUpdate:
    maxSurge: 25%
  subnets:
  - eu-west-1a
---
apiVersion: kops.k8s.io/v1alpha2
kind: InstanceGroup
metadata:
  labels:
    kops.k8s.io/cluster: panic.example.com
  name: apiserver-eu-west-1b
spec:
  image: 099720109477/ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-20210415
  machineType: t4g.large
  maxSize: 1
  minSize: 1
  role: APIServer
  rollingUpdate:
    maxSurge: 25%
  subnets:
  - eu-west-1b
---
apiVersion: kops.k8s.io/v1alpha2
kind: InstanceGroup
metadata:
  labels:
    kops.k8s.io/cluster: panic.example.com
  name: apiserver-eu-west-1c
spec:
  image: 099720109477/ubuntu/images/hvm-ssd/ubuntu-focal-20.04-arm64-server-20210415
  machineType: t4g.large
  maxSize: 1
  minSize: 1
  role: APIServer
  rollingUpdate:
    maxSurge: 25%
  subnets:
  - eu-west-1c
```

```diff
@@ -72,6 +72,7 @@ spec:
         clusterDefaultNodeSelector: "kubernetes.io/role=node"
     name: admission-controller-config.yaml
     roles:
+    - APIServer
     - Master
   - content: |
       apiVersion: audit.k8s.io/v1
@@ -80,6 +81,7 @@ spec:
       - level: Metadata
     name: audit.yaml
     roles:
+    - APIServer
     - Master
   hooks:
   - execContainer:
```


**8. Please run the commands with most verbose logging by adding the `-v 10` flag.
  Paste the logs into this report, or in a gist and provide the gist link here.**
Not `-v 10`, but this is what I have:
```
panic: runtime error: index out of range [1] with length 1
goroutine 1 [running]:
k8s.io/kops/pkg/instancegroups.(*RollingUpdateCluster).rollingUpdateInstanceGroup(0xc00028a840, 0xc000db4cb0, 0x37e11d600, 0x14, 0xc0010ad870)
	pkg/instancegroups/instancegroups.go:154 +0x1454
k8s.io/kops/pkg/instancegroups.(*RollingUpdateCluster).RollingUpdate(0xc00028a840, 0xc000b9d380, 0xc00064f2d0, 0xc00064f2d0, 0xc000622390)
	pkg/instancegroups/rollingupdate.go:173 +0x96f
main.RunRollingUpdateCluster(0x549fe90, 0xc000060100, 0xc00000c330, 0x544ad80, 0xc000182008, 0xc000212500, 0x5d5560, 0xc000be9d68)
	cmd/kops/rollingupdatecluster.go:444 +0x10b3
main.NewCmdRollingUpdateCluster.func1(0xc000a90f00, 0xc0009e3d70, 0x0, 0x3)
	cmd/kops/rollingupdatecluster.go:219 +0x105
k8s.io/kops/vendor/github.com/spf13/cobra.(*Command).execute(0xc000a90f00, 0xc0009e3d40, 0x3, 0x3, 0xc000a90f00, 0xc0009e3d40)
	vendor/github.com/spf13/cobra/command.go:856 +0x2c2
k8s.io/kops/vendor/github.com/spf13/cobra.(*Command).ExecuteC(0x785a8c0, 0x78aa770, 0x0, 0x0)
	vendor/github.com/spf13/cobra/command.go:960 +0x375
k8s.io/kops/vendor/github.com/spf13/cobra.(*Command).Execute(...)
	vendor/github.com/spf13/cobra/command.go:897
main.Execute()
	cmd/kops/root.go:97 +0x8f
main.main()
	cmd/kops/main.go:24 +0x25
```



**9. Anything else do we need to know?**

I had 3x APIServer instance groups, but the asset manifests were misconfigured by me, so those three nodes never joined the cluster. I terminated one manually then a bit later got a panic. The same thing happened when later I terminated the other two.

As the stack trace mentions, the problem seems to lie in the maths around here: https://github.com/kubernetes/kops/blob/v1.21.0-beta.3/pkg/instancegroups/instancegroups.go#L153-L154
