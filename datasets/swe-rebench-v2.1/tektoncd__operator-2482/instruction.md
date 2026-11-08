Tekton operator >= 0.73 raise as error: panic: runtime error: invalid memory address or nil pointer dereference
# Expected Behavior

Deployment on kubernetes of the Tekton Operator (>= 0.73) should not raise an error: `panic: runtime error: invalid memory address or nil pointer dereference` but a more human readable.


# Actual Behavior

Tekton operator >= 0.73 raise as error: panic: runtime error: invalid memory address or nil pointer dereference
```
I1220 15:44:58.104509       1 leaderelection.go:250] attempting to acquire leader lease tekton-operator/tekton-operator-lifecycle.github.com.tektoncd.operator.pkg.reconciler.kubernetes.tektonresult.reconci
I1220 15:45:59.263201       1 leaderelection.go:260] successfully acquired lease tekton-operator/tekton-operator-lifecycle.github.com.tektoncd.operator.pkg.reconciler.shared.tektonconfig.reconciler.00-of-0
{"level":"info","timestamp":"2024-12-20T15:45:59.264Z","logger":"tekton-operator-lifecycle","caller":"leaderelection/context.go:158","msg":"\"tekton-operator-6f69d5b8c9-9rklm_d77cc153-cfe3-4667-9e02-593715
{"level":"info","timestamp":"2024-12-20T15:45:59.268Z","logger":"tekton-operator-lifecycle","caller":"tektonconfig/tektonconfig.go:105","msg":"Reconciling TektonConfig","commit":"dbf2fac-dirty","knative.de
{"level":"error","timestamp":"2024-12-20T15:45:59.330Z","logger":"tekton-operator-lifecycle","caller":"tektonconfig/reconciler.go:295","msg":"Returned an error","commit":"dbf2fac-dirty","knative.dev/pod":"
{"level":"error","timestamp":"2024-12-20T15:45:59.331Z","logger":"tekton-operator-lifecycle","caller":"controller/controller.go:566","msg":"Reconcile error","commit":"dbf2fac-dirty","knative.dev/pod":"tekt
{"level":"info","timestamp":"2024-12-20T15:45:59.331Z","logger":"tekton-operator-lifecycle","caller":"tektonconfig/tektonconfig.go:105","msg":"Reconciling TektonConfig","commit":"dbf2fac-dirty","knative.de
{"level":"info","timestamp":"2024-12-20T15:45:59.331Z","logger":"tekton-operator-lifecycle.event-broadcaster","caller":"record/event.go:364","msg":"Event(v1.ObjectReference{Kind:\"TektonConfig\", Namespace
{"level":"error","timestamp":"2024-12-20T15:45:59.365Z","logger":"tekton-operator-lifecycle","caller":"tektonconfig/reconciler.go:295","msg":"Returned an error","commit":"dbf2fac-dirty","knative.dev/pod":"
{"level":"error","timestamp":"2024-12-20T15:45:59.365Z","logger":"tekton-operator-lifecycle","caller":"controller/controller.go:566","msg":"Reconcile error","commit":"dbf2fac-dirty","knative.dev/pod":"tekt
{"level":"info","timestamp":"2024-12-20T15:45:59.365Z","logger":"tekton-operator-lifecycle","caller":"tektonconfig/tektonconfig.go:105","msg":"Reconciling TektonConfig","commit":"dbf2fac-dirty","knative.de
{"level":"info","timestamp":"2024-12-20T15:45:59.365Z","logger":"tekton-operator-lifecycle.event-broadcaster","caller":"record/event.go:364","msg":"Event(v1.ObjectReference{Kind:\"TektonConfig\", Namespace
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x1436a0c]

goroutine 408 [running]:
github.com/tektoncd/operator/pkg/reconciler/shared/tektonconfig/upgrade.upgradePipelineProperties({0x1d432e8, 0x4001264060}, 0x1a566ba?, {0x1f?, 0x0?}, {0xffff53a791b8, 0x40002ff350}, 0x40011475d8?)
    github.com/tektoncd/operator/pkg/reconciler/shared/tektonconfig/upgrade/pre_upgrade.go:70 +0x8c
github.com/tektoncd/operator/pkg/reconciler/shared/tektonconfig/upgrade.(*Upgrade).executeUpgrade(0x4000068200, {0x1d432e8, 0x4001264060}, {0x2ccefc0, 0x2, 0x0?}, 0x1)
    github.com/tektoncd/operator/pkg/reconciler/shared/tektonconfig/upgrade/upgrade.go:99 +0x2ec
github.com/tektoncd/operator/pkg/reconciler/shared/tektonconfig/upgrade.(*Upgrade).RunPreUpgrade(...)
    github.com/tektoncd/operator/pkg/reconciler/shared/tektonconfig/upgrade/upgrade.go:65
github.com/tektoncd/operator/pkg/reconciler/shared/tektonconfig.(*Reconciler).ReconcileKind(0x40003ded80, {0x1d432e8, 0x4001264060}, 0x400122a408)
    github.com/tektoncd/operator/pkg/reconciler/shared/tektonconfig/tektonconfig.go:117 +0x2ac
github.com/tektoncd/operator/pkg/client/injection/reconciler/operator/v1alpha1/tektonconfig.(*reconcilerImpl).Reconcile(0x40004e4820, {0x1d432e8, 0x4001264030}, {0x40005b31e6, 0x6})
    github.com/tektoncd/operator/pkg/client/injection/reconciler/operator/v1alpha1/tektonconfig/reconciler.go:236 +0x3d4
knative.dev/pkg/controller.(*Impl).processNextWorkItem(0x400070dc80)
    knative.dev/pkg@v0.0.0-20240416145024-0f34a8815650/controller/controller.go:542 +0x3b8
knative.dev/pkg/controller.(*Impl).RunContext.func3()
    knative.dev/pkg@v0.0.0-20240416145024-0f34a8815650/controller/controller.go:491 +0x5c
created by knative.dev/pkg/controller.(*Impl).RunContext in goroutine 392
    knative.dev/pkg@v0.0.0-20240416145024-0f34a8815650/controller/controller.go:489 +0x298
```

# Steps to Reproduce the Problem

1. Create a kind cluster
2. Deploy the Tekton Operator >= 0.73
3. Deploy the following Tekton Config: https://github.com/ch007m/fork-konflux-ci/blob/idpbuilder/idp/dependencies/tekton-config/tekton-config.yml


# Additional Info

- Kubernetes version:

  **Output of `kubectl version`:**

```
Client Version: v1.31.2
Kustomize Version: v5.4.2
Server Version: v1.30.3
```

- Tekton Pipeline version:

  **Output of `tkn version` or `kubectl get pods -n tekton-pipelines -l app=tekton-pipelines-controller -o=jsonpath='{.items[0].metadata.labels.version}'`**

```
❯ tkn version
Client version: 0.38.1
Pipeline version: unknown, pipeline controller may be installed in another namespace please use tkn version -n {namespace}
Operator version: v0.74.0
```

### Additional contract requirements

- The pre-upgrade step that enables pipeline step actions must not panic when the TektonConfig's `spec.pipeline.enable-step-actions` field is unset (nil). An unset value must be treated the same as `false`: the step must enable step actions by setting `spec.pipeline.enable-step-actions` to `true` and must return no error.
- When no TektonConfig resource exists, the step must return no error.
