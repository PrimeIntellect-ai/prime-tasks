'Error generating params' error when using JSON array in Git files generator file
An 'error generating params' error is output when using the following ApplicationSet on the specified repo.

The following ApplicationSet will trigger the error:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
  - git:
      revision: HEAD
      repoURL: https://github.com/jgwest/argocd-example-apps.git
      files:
        - path: appset-examples/git-files-example/config/clusters.json   # <--- this line is the important one
  template:
    metadata:
      name: '{{cluster.name}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/jgwest/argocd-example-apps.git
        targetRevision: HEAD
        path: appset-examples/git-files-example/apps/guestbook/{{appVersions.guestbook}}
      destination:
        server: https://kubernetes.default.svc
        namespace: guestbook
```

This is because the `cluster.json` (referenced above) looks like this [(source)](https://github.com/jgwest/argocd-example-apps/blob/master/appset-examples/git-files-example/config/clusters.json):
```yaml
[
  {
    "account": "123456",
    "asset_id": "11223344",
    // ...
  },
  {
    "account": "456789",
    "asset_id": "55667788",
    // ...
  }
]
```
Notice that this is a JSON array (of objects), rather than a single JSON object... it appears the current Git file generator parsing code assumes that files will only be JSON objects, not JSON arrays.


Error log:

```
INFO[0448] Trace                                         args="[git clean -fdx]" dir="/tmp/https:__github.com_jgwest_argocd-example-apps" operation_name="exec git" time_ms=4.000146000000001
ERRO[0448] error generating params                       error="json: cannot unmarshal array into Go value of type map[string]interface {}" generator="&{0xc0003a4f00}"
2021-01-26T12:01:54.853-0500	ERROR	controller-runtime.manager.controller.applicationset	Reconciler error	{"reconciler group": "argoproj.io", "reconciler kind": "ApplicationSet", "name": "guestbook", "namespace": "argocd", "error": "json: cannot unmarshal array into Go value of type map[string]interface {}"}
```

### Additional contract requirements

- When retrieving file paths or file contents fails, the returned error must include the underlying error message, including `paths error` and `staging config file get content error` in the tested cases.
