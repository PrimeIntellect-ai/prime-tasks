Do not print additional warnings from go-client
After the latest upgrade of K8S libs. (#401) the stderr output contains warnings from the API client. While these are certainly useful in scenarios like `kubectl`, I think these are undesirable in our case and also don't follow the same logging format:

```shell
$./bin/kubent-darwin-amd64
4:32PM INF >>> Kube No Trouble `kubent` <<<
4:32PM INF version dev (git sha dev)
4:32PM INF Initializing collectors and retrieving data
W1124 16:32:06.765179   25068 gcp.go:119] WARNING: the gcp auth plugin is deprecated in v1.22+, unavailable in v1.26+; use gcloud instead.
To learn more, consult https://cloud.google.com/blog/products/containers-kubernetes/kubectl-auth-changes-in-gke
4:32PM INF Target K8s version is 1.23.8-gke.1900
W1124 16:32:11.190950   25068 warnings.go:70] policy/v1beta1 PodSecurityPolicy is deprecated in v1.21+, unavailable in v1.25+
W1124 16:32:15.931515   25068 warnings.go:70] policy/v1beta1 PodSecurityPolicy is deprecated in v1.21+, unavailable in v1.25+
4:32PM INF Retrieved 10 resources from collector name=Cluster
```
