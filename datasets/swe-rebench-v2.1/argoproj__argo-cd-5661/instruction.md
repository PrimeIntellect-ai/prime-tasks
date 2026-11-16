Argo CD too frequently fetches Helm repo index that results in a lot of traffic
**Describe the bug**

Argo CD allows creating an application that points directly to the Helm repository. If chart version is not specified explicitly then Argo CD loads whole repository index multiple time per second that results in a lot of traffic and might be costly.

**To Reproduce**

The issue can be reproduced by just creating an application that points directly to the Helm repository. Every reconciliation argocd loads repo index file.


**Expected behavior**

The index file should be cached or the number of queries should be reduced.

**Version**

```shell
v1.8.6
```

### Additional contract requirements

- Helm repository index caching is enabled by the environment variable
  `ARGOCD_HELM_INDEX_CACHE_DURATION`, whose value is a Go duration string (for
  example `60s`). When the variable is unset or evaluates to zero, index caching
  is disabled.
- When caching is enabled, repeated `GetIndex(false)` calls for the same
  repository must not re-download the index within the cache duration, while
  `GetIndex(true)` must always bypass the cache and download a fresh index.
