injectLabels should not inject on RoleList and RoleBindingList objects
Hi,

We enabled garbagecollection via injectLabels: true on our environments (tk 0.10.0) and we hit a bug with kube-prometheus.

Prometheus generates RoleList and RoleBindingList object kinds and labels are not allowed in its metadata:

`error: error validating "STDIN": error validating data: ValidationError(RoleList.metadata): unknown field "labels" in io.k8s.apimachinery.pkg.apis.meta.v1.ListMeta; if you choose to ignore these errors, turn validation off with --validate=false`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleList
metadata:
  labels:
    tanka.dev/environment: someEnv
items:
- apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    name: prometheus-k8s
    namespace: default
  rules:
  - apiGroups:
    - ""
    resources:
    - services
    - endpoints
    - pods
    verbs:
    - get
    - list
    - watch
...
...
```

### Additional contract requirements

- With label injection enabled, `RoleList` and `RoleBindingList` objects must not receive the `tanka.dev/environment` label in their metadata.
- With label injection enabled, other Kubernetes objects in the same environment keep receiving the `tanka.dev/environment` label.
