helm repo pull does not use CA File
Output of `helm version`:

version.BuildInfo{Version:"v3.0+unreleased", GitCommit:"84de17e7e5255e5033967f005d4b4c05c024317c", GitTreeState:"dirty", GoVersion:"go1.13.4"}

Also applies for the release:
version.BuildInfo{Version:"v3.0.0", GitCommit:"e29ce2a54e96cd02ccfce88bee4f58bb6e2a28b6", GitTreeState:"clean", GoVersion:"go1.13.4"}

Output of `kubectl version`:
N/A

Cloud Provider/Platform (AKS, GKE, Minikube etc.):
N/A


We have a custom helm chart repo on a self-signed certificate. Pulling does not work unless using absolute URLs.

```
$ helm pull example/chart
Error: Get https://servername/repository/helm/chart-0.0.1.tgz: x509: certificate signed by unknown authority
```

Even passing `--cert-file` on the command line does not help. (the ca cert file is in the repo config, so should be picked up from there)

I have a patch locally that address the issue with not looking at the repo config. Will look into the issue with the command flag not being used either, too.
Will push a PR as soon as I've cleaned it up a bit.

### Additional contract requirements

- Add a public function `WithTLSClientConfig(certFile string, keyFile string, caFile string) getter.Option` in package `helm.sh/helm/v3/pkg/getter`. Applying it to an HTTP getter configures the underlying HTTP client to use the supplied TLS material for mutual TLS and server-certificate verification; an empty argument leaves the corresponding TLS setting unchanged.
- When a chart is resolved from a repository whose configuration specifies `certFile`, `keyFile`, and/or `caFile`, the getter used to fetch the chart must be configured with those repository TLS settings.
- TLS certificate, key, and CA paths supplied as command-line flags to `helm pull` are used for the chart download; the CA is used to verify the server and the certificate/key are presented for mutual TLS.
