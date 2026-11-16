Helm does not validate release name during install, but validates it during uninstall
<!-- If you need help or think you have found a bug, please help us with your issue by entering the following information (otherwise you can delete this text): -->

Output of `helm version`:
`helm.sh/helm/v3 v3.5.0` (from `go.mod`)


Cloud Provider/Platform (AKS, GKE, Minikube etc.):
Local

Scenario:

1. While writing a UT to test `helm install` and `helm uninstall` from my Go program, I repeatedly hit the error: `'uninstall: Release name is invalid: testNamespace-chart-name-id1-id2`.

2. The install went fine with no errors.

3. Looking at the source for `helm uninstall`, I see [here](https://github.com/helm/helm/blob/master/pkg/action/uninstall.go#L66-L68) that Helm validates the release name to [conform to the regex](https://github.com/helm/helm/blob/master/pkg/chartutil/validate_name.go#L30) `[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*`.

4. A similar check is present during an `upgrade` and `rollback`, but absent during an `install`.

5. I removed the camel-casing in my release name and things work fine.

Expected behaviour:

If the release name is invalid, an error should be encountered immediately while installing the release and not while uninstalling it.
