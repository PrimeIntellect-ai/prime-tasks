Server side apply
Some CRDs inside `kube-prometheus-stack` fails to apply due to large size.

> The CustomResourceDefinition "prometheuses.monitoring.coreos.com" is invalid: metadata.annotations: Too long: must have at most 262144 bytes

The proposed way for installation is using the `--server-side` flag for `kubectl apply`.
Is there a way to support that with tanka?
Currently, I'm using this as a workaround.

```bash
#!/usr/bin/env bash

rm -rf manifests
tk export manifests/ environments/prod -t 'CustomResourceDefinition.*'
find manifests -type f ! -name '*.yaml' -delete
kubectl apply --server-side -f manifests
tk apply environments/prod -t '!CustomResourceDefinition.*'
```

### Additional contract requirements

- `pkg/kubernetes/client.ApplyOpts` exposes a public field `ServerSide bool`. When it is set, the `kubectl apply` command run by the client includes the `--server-side` flag.
- `pkg/tanka.ApplyOpts` exposes a public field `ServerSide bool`. When `tanka.Apply` is called with `ServerSide` set, the `kubectl apply` command it runs includes the `--server-side` flag.
