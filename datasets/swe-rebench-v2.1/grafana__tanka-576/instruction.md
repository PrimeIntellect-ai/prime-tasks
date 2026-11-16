Helm template --api-versions flag incorrectly formatted
If you pass `apiVersions` to the Helm template function:

```jsonnet
{
  local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet',
  local helm = tanka.helm.new(std.thisFile),
  app: helm.template('my-app', '../../charts/my-app', {
    values: {
      serviceMonitor: {
        enabled: true,
      },
    },
    apiVersions: ['v1', 'apps/v1', 'monitoring.coreos.com/v1'],
  }),
}
```

then Helm will be called with the API versions as a comma-separated list:

```sh
--api-versions=v1,apps/v1,monitoring.coreos.com/v1
```

However, the [`--api-versions` flag](https://github.com/helm/helm/blob/47c8f48f209f363807c8fb9f17ef072d7ae32139/cmd/helm/template.go#L184) is [supposed to be specified multiple times](https://pkg.go.dev/github.com/spf13/pflag#StringArrayVarP), not as a comma-separated list:

```sh
--api-versions=v1 --api-versions=apps/v1 --api-versions=monitoring.coreos.com/v1
```
