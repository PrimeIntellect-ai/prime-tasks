Tanka incorrectly specifies a namespace when creating a Namespace
Tanka applies the spec.json's namespace to a Namespace's metadata, which can be confusing (and is a no-op):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  namespace: testing
```

To reproduce, create an environment using a namespace of `testing` and then use this for the main.jsonnet file:

```jsonnet
(import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet') +
{
  ns: $.core.v1.namespace.new('dev'),
}
```

### Additional contract requirements

Tanka must not inject the environment's configured namespace into the `metadata.namespace` of the manifests it produces; objects without an explicit namespace must be left without one, so that `kubectl` decides the effective namespace.

Add a function `separateMissingNamespace(in manifest.List, exists map[string]bool) (ready manifest.List, missingNamespace manifest.List)` in package `client` (`pkg/kubernetes/client`). It splits `in` into manifests that can be processed immediately (`ready`) and those that reference an unknown namespace (`missingNamespace`). A manifest belongs to `ready` when its `metadata.namespace` is empty or when `exists[namespace]` is true; a manifest with a non-empty namespace for which `exists[namespace]` is false belongs to `missingNamespace`.

Add a function `patchKubeconfig(file string, e []string) []string` in package `client` (`pkg/kubernetes/client`). Given the path `file` of a kubeconfig fragment and an environment slice `e` of `KEY=VALUE` entries, it returns a new environment slice in which `KUBECONFIG` is prefixed with `file:` followed by a colon. If `e` contains no `KUBECONFIG` entry, the default `$HOME/.kube/config` is used as the existing value. All other entries of `e` are preserved, and the returned slice is sorted for deterministic order.
