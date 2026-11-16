Allow to set the same header multiple time in Prometheus Datascources
**What would you like to be added**:

We use [prom-label-proxy](https://github.com/prometheus-community/prom-label-proxy) to setup some multi-tenant Prometheus. Launched with:

```shell
prom-label-proxy \
  --insecure-listen-address=0.0.0.0:8080 \
  --upstream=http://prometheus-stack-kube-prom-prometheus.prometheus-stack:9090/ \
  --label=namespace \
  --internal-listen-address=0.0.0.0:9090 \
  --enable-label-apis=true \
  --error-on-replace=true \
  --header-name=X-Namespace \
```

We have a tenant which needs access to 2 namespaces `ns1` and `ns2`.

This can be done by setting the header twice:

```
X-Namespace: ns1
X-Namespace: ns2
```

But this doesn't work when set from UI:

![image](https://github.com/grafana/grafana-plugin-sdk-go/assets/741106/6f607952-5f1e-4e2b-bda9-db2643c2cea1)

**Why is this needed**:

See above

**Code references**:

[HIDDEN]
