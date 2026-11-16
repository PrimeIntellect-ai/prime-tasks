Kubernetes 1.33 does not accept --cloud-config
/kind bug

kOps CI testing Kubernetes master is red since 2025-02-17, https://testgrid.k8s.io/kops-latest#kops-aws-amd64-conformance

`kube-apiserver --cloud-config` and `--cloud-provider` have been deprecated for quite some time, now they're removed for real and the newest API server won't come up.

**1. What `kops` version are you running? The command `kops version`, will display
 this information.**

v1.32.0-beta.1-20-g99ba10e2d5 (current [latest-ci-updown-green.txt](https://storage.googleapis.com/k8s-staging-kops/kops/releases/markers/master/latest-ci-updown-green.txt))

**2. What Kubernetes version are you running? `kubectl version` will print the
 version if a cluster is running or provide the Kubernetes version specified as
 a `kops` flag.**

Latest master,  https://storage.googleapis.com/k8s-release-dev/ci/v1.33.0-alpha.2.28+7fc8a86381d874

**3. What cloud provider are you using?**
AWS

**4.  What is the simplest way to reproduce this issue?**
See CI e.g. https://prow.k8s.io/view/gs/kubernetes-ci-logs/logs/e2e-kops-aws-amd64-conformance/1892186901553614848

**5. What happened after the commands executed?**
The API server fails with `Error: unknown flag: --cloud-config`

**6. What did you expect to happen?**
Green CI :-)
