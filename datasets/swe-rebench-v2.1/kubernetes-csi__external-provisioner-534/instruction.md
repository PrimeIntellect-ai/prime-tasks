Panic when using unsupported data source
Occurs with version v2.0.4 or with canary.

If you enable the AnyVolumeDataSource feature gate, and create a PVC with a data source that is some CRD other than a snapshot, the external provisioner panics.

I1203 14:04:27.518582       1 connection.go:182] GRPC call: /csi.v1.Controller/CreateVolume
I1203 14:04:27.518600       1 controller.go:869] Started provisioner controller csi.test.net_test-csi-controller-86844bf58c-p5zxh_a0581d73-b8b9-4033-9b0a-87907718bf35!
I1203 14:04:27.518639       1 controller.go:1317] provision "default/pvc1" class "standard": started
I1203 14:04:27.518680       1 controller.go:485] DataSource specified (Hello) is not supported by the provisioner, waiting for an external data populator to create the volume
E1203 14:04:27.518818       1 runtime.go:78] Observed a panic: "invalid memory address or nil pointer dereference" (runtime error: invalid memory address or nil pointer dereference)
goroutine 126 [running]:
k8s.io/apimachinery/pkg/util/runtime.logPanic(0x16ad960, 0x24a3ce0)
	/workspace/vendor/k8s.io/apimachinery/pkg/util/runtime/runtime.go:74 +0xa6
k8s.io/apimachinery/pkg/util/runtime.HandleCrash(0x0, 0x0, 0x0)
	/workspace/vendor/k8s.io/apimachinery/pkg/util/runtime/runtime.go:48 +0x89
panic(0x16ad960, 0x24a3ce0)
	/go/pkg/csiprow.XXXXFoAlfI/go-1.15/src/runtime/panic.go:969 +0x175
sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller.(*ProvisionController).provisionClaimOperation(0xc000484c80, 0x1abbd00, 0xc000046020, 0xc000093c00, 0x1, 0x0, 0x0, 0x1800920)
	/workspace/vendor/sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller/controller.go:1420 +0x12da
sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller.(*ProvisionController).syncClaim(0xc000484c80, 0x1abbd00, 0xc000046020, 0x1887340, 0xc000093c00, 0xc0005d7d50, 0x1)
	/workspace/vendor/sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller/controller.go:1072 +0x10e
sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller.(*ProvisionController).syncClaimHandler(0xc000484c80, 0x1abbd00, 0xc000046020, 0xc00036ff80, 0x24, 0x414e9b, 0xc00059eca8)
	/workspace/vendor/sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller/controller.go:1040 +0xca
sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller.(*ProvisionController).processNextClaimWorkItem.func1(0xc000484c80, 0xc00059ee18, 0x163b640, 0xc000528e30, 0x0, 0x0)
	/workspace/vendor/sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller/controller.go:941 +0x11d
sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller.(*ProvisionController).processNextClaimWorkItem(0xc000484c80, 0x1abbd00, 0xc000046020, 0x0)
	/workspace/vendor/sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller/controller.go:963 +0x71
sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller.(*ProvisionController).runClaimWorker(0xc000484c80, 0x1abbd00, 0xc000046020)Provision
	/workspace/vendor/sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller/controller.go:909 +0x3f
sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller.(*ProvisionController).Run.func1.2()
	/workspace/vendor/sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller/controller.go:865 +0x3c
k8s.io/apimachinery/pkg/util/wait.BackoffUntil.func1(0xc0005f7da0)
	/workspace/vendor/k8s.io/apimachinery/pkg/util/wait/wait.go:155 +0x5f
k8s.io/apimachinery/pkg/util/wait.BackoffUntil(0xc0005f7da0, 0x1a7e420, 0xc0006044e0, 0x1, 0x0)
	/workspace/vendor/k8s.io/apimachinery/pkg/util/wait/wait.go:156 +0xad
k8s.io/apimachinery/pkg/util/wait.JitterUntil(0xc0005f7da0, 0x3b9aca00, 0x0, 0x1, 0x0)
	/workspace/vendor/k8s.io/apimachinery/pkg/util/wait/wait.go:133 +0x98
k8s.io/apimachinery/pkg/util/wait.Until(0xc0005f7da0, 0x3b9aca00, 0x0)
	/workspace/vendor/k8s.io/apimachinery/pkg/util/wait/wait.go:90 +0x4d
created by sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller.(*ProvisionController).Run.func1
	/workspace/vendor/sigs.k8s.io/sig-storage-lib-external-provisioner/v6/controller/controller.go:865 +0x46a
panic: runtime error: invalid memory address or nil pointer dereference [recovered]
	panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x20 pc=0x14ffc3a]


[HIDDEN]

### Additional contract requirements

- When handling an unsupported data source, Provision must return a non-nil error.
