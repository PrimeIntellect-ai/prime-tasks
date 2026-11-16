Telegraf-istio sidecar is killed with OOM
We use `--enable-istio-injection=true` to inject sidecar for Envoy instances. The default memory limit is 200Mi. OOM killer kills the sidecar approximately every 10 minutes. With the sidecar instance fails.
For workloads we can tune limits with metadata annotations. It should be good to add annotations to workloads to tune resources for telegraf-istio sidecar. Of course, it's better if we can tune memory/cpu/ephemeral storage globally in Istio-operator config (not sure if it's possible).

### Additional contract requirements

Workload annotations can tune the Telegraf-Istio sidecar's CPU and memory resource requests and limits. Use `telegraf.influxdata.com/istio-requests-cpu`, `telegraf.influxdata.com/istio-requests-memory`, `telegraf.influxdata.com/istio-limits-cpu`, and `telegraf.influxdata.com/istio-limits-memory` for the corresponding values. These settings apply to the Telegraf-Istio sidecar and do not change the regular Telegraf sidecar's resources.
