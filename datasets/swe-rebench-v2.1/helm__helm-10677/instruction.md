helm lint should allow specifying --kube-version flag
We're currently using `helm lint` to find deprecated API versions in our charts, failing CI on warnings. However, helm assumes that the target Kubernetes version is the one specified through the k8sVersionMajor/k8sVersionMinor vars. The only way to work around this is rebuilding helm with LDFLAGS, or using a Helm release with the proper defaults.

The command-line flag `--kube-version` currently exists with `helm template`, `helm lint` should replicate the behaviour:
https://github.com/helm/helm/pull/9040

### Additional contract requirements

When a Kubernetes version is supplied to `helm lint`, chart templates must observe that version in their Kubernetes capabilities. When it is omitted, lint must retain its existing Kubernetes version defaults.
