Add missing Kubernetes version validation
We must ensure Kubernetes version is set when either of the following options is configured:
- manifest URLs
- local manifests
- Helm charts
