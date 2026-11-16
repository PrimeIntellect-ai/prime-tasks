Panic when adding annotations to ConfigMap
### What happened?

When adding annotations to the cluster's config map via the [`configMap` property of `FoundationDBClusterSpec`](https://github.com/FoundationDB/fdb-kubernetes-operator/blob/main/docs/cluster_spec.md#foundationdbclusterspec), the cluster controller panics with the following:

```
panic: assignment to entry in nil map [recovered]
	panic: assignment to entry in nil map

goroutine 205 [running]:
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Reconcile.func1()
	/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.14.7/pkg/internal/controller/controller.go:119 +0x1da
panic({0x16e5ee0?, 0x1b44360?})
	/usr/local/go/src/runtime/panic.go:785 +0x132
[HIDDEN]
github.com/FoundationDB/fdb-kubernetes-operator/controllers.updateConfigMap.reconcile({}, {0x1b60fd8, 0xc0008e8360}, 0xc000218380, 0xc000845508, 0x0?, {{0x1b64350?, 0xc000a8e000?}, 0xc000a8e000?})
	/workspace/controllers/update_config_map.go:68 +0x526
github.com/FoundationDB/fdb-kubernetes-operator/controllers.runClusterSubReconciler({0x1b60fd8, 0xc0008e8360}, {{0x1b64350?, 0xc0008e8630?}, 0xc000a82100?}, {0x1b47820, 0x27ebd20}, 0xc000218380, 0xc000845508, 0x0)
	/workspace/controllers/cluster_controller.go:260 +0x2e6
github.com/FoundationDB/fdb-kubernetes-operator/controllers.(*FoundationDBClusterReconciler).Reconcile(0xc000218380, {0x1b60fd8, 0xc0008e8360}, {{{0xc0002c89d0?, 0x0?}, {0xc0005ea0d8?, 0xc0008e8360?}}})
	/workspace/controllers/cluster_controller.go:214 +0xe93
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Reconcile(0x1b60fd8?, {0x1b60fd8?, 0xc0008e8360?}, {{{0xc0002c89d0?, 0x1633b60?}, {0xc0005ea0d8?, 0x4172cb?}}})
	/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.14.7/pkg/internal/controller/controller.go:122 +0xa5
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).reconcileHandler(0xc000349860, {0x1b61010, 0xc0004c0fa0}, {0x17441e0, 0xc0008acbe0})
	/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.14.7/pkg/internal/controller/controller.go:323 +0x325
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).processNextWorkItem(0xc000349860, {0x1b61010, 0xc0004c0fa0})
	/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.14.7/pkg/internal/controller/controller.go:274 +0x1a8
sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func2.2()
	/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.14.7/pkg/internal/controller/controller.go:235 +0x73
created by sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func2 in goroutine 92
	/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.14.7/pkg/internal/controller/controller.go:231 +0x50c
```

### What did you expect to happen?

The controller should not crash, and the custom annotations should be added to the `ConfigMap` managed by the controller.

[HIDDEN]

### How can we reproduce it (as minimally and precisely as possible)?

Add a `configMap` property to a cluster definition that adds a new annotation:

```yaml
configMap:
  metadata:
    annotations:
      panics: "unfortunately yes"
```

### Anything else we need to know?

_No response_

### FDB Kubernetes operator

Operator version 1.55.0 (but it looks like it would still be an issue in 2.0.0).

### Kubernetes version

Client Version: v1.31.4
Kustomize Version: v5.4.2
Server Version: v1.31.5-eks-8cce635

### Cloud provider

AWS/EKS
