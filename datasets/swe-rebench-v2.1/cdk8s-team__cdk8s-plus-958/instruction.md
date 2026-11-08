Add support for configuring scheme in http probes
Here is the k8s documentation https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#http-probes

### Additional contract requirements

- HTTP GET probes can be configured to use HTTP or HTTPS, and the selected scheme is reflected in the emitted Kubernetes probe.
- The scheme option is available through the public TypeScript API, allowing callers to provide it without a type escape.
