Swap misidentified due to trailing newline in file
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!

If the matter is security related, please disclose it privately via https://kubernetes.io/security/
-->


**What happened**:

While deploying NFD 0.16.0 on a k8s 1.30.2 node (Ubuntu 22.04), I noticed it assigned `memory-swap=true` despite swap not being enabled on this system.

**What you expected to happen**:

I expected NFD to recognize that no swap device is registered

**How to reproduce it (as minimally and precisely as possible)**:

As far as I can tell, the issue is that `/proc/swaps` ends in a newline character `\n`, while the testdata has no such trailing newline. So any system which has `/proc/swaps` with a trailing newline will be misidentified.

**Anything else we need to know?**:

This system is a VM which was initially created with swap which was then removed as part of the k8s provisioning process. `/proc/swaps` contains only the header line and a single `\n` character now.

**Environment**:
- Kubernetes version (use `kubectl version`): v1.30.2
- Cloud provider or hardware configuration: VM on local proxmox instance
- OS (e.g: `cat /etc/os-release`): Ubuntu 22.04
- Kernel (e.g. `uname -a`): 5.15.0-113-generic
- Install tools:
  - Cluster created with `kubeadm version: &version.Info{Major:"1", Minor:"30", GitVersion:"v1.30.2", GitCommit:"39683505b630ff2121012f3c5b16215a1449d5ed", GitTreeState:"clean", BuildDate:"2024-06-11T20:27:59Z", GoVersion:"go1.22.4", Compiler:"gc", Platform:"linux/amd64"}`
  - Helm: [Terraform provider](https://registry.terraform.io/providers/hashicorp/helm/2.14.0) version 2.14.0

[HIDDEN]
