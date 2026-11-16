capk manager causes a segmentation fault when cluster is created with the kubevirtci tool
**What steps did you take and what happened:**
The cluster was created and the tests run using these steps:
https://docs.google.com/document/d/1kPLk1KfGvAX4vUV5DOpvekPGr4wQF6Iait4M-YBq1tM/edit

[A clear and concise description on how to REPRODUCE the bug.]
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x142579e]

goroutine 471 [running]:
sigs.k8s.io/cluster-api-provider-kubevirt/controllers.(*KubevirtMachineReconciler).deleteKubevirtBootstrapSecret(0x19c2068, 0xc000359e50, {0x19d2b90, 0xc0000914a0}, {0xc00042ada0, 0x1e})
        /workspace/controllers/kubevirtmachine_controller.go:579 +0x5e
sigs.k8s.io/cluster-api-provider-kubevirt/controllers.(*KubevirtMachineReconciler).reconcileDelete(0xc0006d6b80, 0xc000359e50)
        /workspace/controllers/kubevirtmachine_controller.go:375 +0x185
sigs.k8s.io/cluster-api-provider-kubevirt/controllers.(*KubevirtMachineReconciler).Reconcile(0xc0006d6b80, {0x19a57f8, 0xc000a2c690}, {{{0xc000acb6c0, 0x16b4be0}, {0xc000047620, 0x30}}})
        /workspace/controllers/kubevirtmachine_controller.go:161 +0xb1c
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Reconcile(0xc0000b38c0, {0x19a57f8, 0xc000a2c660}, {{{0xc000acb6c0, 0x16b4be0}, {0xc000047620, 0x413834}}})

**What did you expect to happen:**


**Anything else you would like to add:**
[Miscellaneous information that will assist in solving the issue.]


**Environment:**
Local
- Cluster-api version:
- Cluster-api-provider-kubevirt version:
- Kubernetes version: (use `kubectl version`):
- KubeVirt version:
- OS (e.g. from `/etc/os-release`):

/kind bug
[One or more /area label. See https://github.com/kubernetes-sigs/cluster-api-provider-kubevirt/labels?q=area for the list of labels]
