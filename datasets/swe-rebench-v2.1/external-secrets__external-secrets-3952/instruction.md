kubernetes-provider auth broken after 0.9.20
**Describe the bug**
It seems that after the implementation of this feature for kubernetes provider on release v0.9.20:

> add AuthRef to kubernetes provider fixes https://github.com/external-secrets/external-secrets/issues/3627 by @kaedwen in https://github.com/external-secrets/external-secrets/pull/3628

seems that stoped working only with "auth:" it gives the error:  could not get provider client: failed to prepare auth: no auth provider given

**To Reproduce**
Steps to reproduce the behavior:
Install version v.0.9.20 or newer

deploy a yaml like this:

``` yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: k8s-secretstore
spec:
  provider:
    kubernetes:
      remoteNamespace: shared-secrets
      server:
        url: "https://x.x.x.x:6443"
        caProvider:
          type: ConfigMap
          name: kube-root-ca
          key: ca.crt
          namespace: "external-secrets"
      auth:
        cert:
          clientCert:
            name: "cluster-client"
            key: "tls.crt"
          clientKey:
            name: "cluster-client"
            key: "tls.key"
```

**Expected behavior**
Keep working with auth

**Screenshots**
This is the status of kind: SecretStore
``` yaml
status:
  capabilities: ReadWrite
  conditions:
    - lastTransitionTime: '2024-09-18T13:11:54Z'
      message: unable to create client
      reason: InvalidProviderConfig
      status: 'False'
      type: Ready
```

And the two lines on logs that are generated constantly with the error on app.kubernetes.io/name=external-secrets pod
``` jsonl
{"level":"error","ts":1726665196.5949998,"logger":"controllers.ClusterSecretStore","msg":"unable to validate store","clustersecretstore":{"name":"k8s-alm-secretstore"},"error":"could not get provider client: failed to prepare auth: no auth provider given","stacktrace":"github.com/external-secrets/external-secrets/pkg/controllers/secretstore.reconcile\n\t/home/runner/work/external-secrets/external-secrets/pkg/controllers/secretstore/common.go:69\ngithub.com/external-secrets/external-secrets/pkg/controllers/secretstore.(*ClusterStoreReconciler).Reconcile\n\t/home/runner/work/external-secrets/external-secrets/pkg/controllers/secretstore/clustersecretstore_controller.go:65\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller[...]).Reconcile\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.19.0/pkg/internal/controller/controller.go:116\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller[...]).reconcileHandler\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.19.0/pkg/internal/controller/controller.go:303\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller[...]).processNextWorkItem\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.19.0/pkg/internal/controller/controller.go:263\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller[...]).Start.func2.2\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.19.0/pkg/internal/controller/controller.go:224"}
{"level":"error","ts":1726665196.6100624,"msg":"Reconciler error","controller":"clustersecretstore","controllerGroup":"external-secrets.io","controllerKind":"ClusterSecretStore","ClusterSecretStore":{"name":"k8s-alm-secretstore"},"namespace":"","name":"k8s-alm-secretstore","reconcileID":"a83fe0c9-b660-44e4-985f-b5d5c827ea95","error":"could not get provider client: failed to prepare auth: no auth provider given","stacktrace":"sigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller[...]).reconcileHandler\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.19.0/pkg/internal/controller/controller.go:316\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller[...]).processNextWorkItem\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.19.0/pkg/internal/controller/controller.go:263\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller[...]).Start.func2.2\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.19.0/pkg/internal/controller/controller.go:224"}
```

**Additional context**
Going back to 0.9.19 works perfect
