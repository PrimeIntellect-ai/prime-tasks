Client doesn't implement provideClusterInfo
**What you expected to happen**:
A Python script provided with a kubeconfig that contains a user exec section to get a client certificate should connect to the cluster.

The kubeconfig contains this section:
```
users:
- name: my-garden-cluster
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1
      args:
      - get-client-certificate
      command: kubectl-gardenlogin
      env: null
      installHint: Follow the instructions on https://github.com/gardener/gardenlogin#installation
        to install gardenlogin
      interactiveMode: IfAvailable
      provideClusterInfo: true
```

Running a Kubernetes Python script with this kubeconfig produces the following error:

```
Error: failed to complete command options: ExecCredential does not contain cluster information
Usage:
  gardenlogin get-client-certificate [flags]
```

### Additional contract requirements

- `ExecProvider.__init__` accepts an optional third argument `cluster`, the cluster information taken from the kubeconfig. When the exec configuration requests cluster information, the cluster information from the kubeconfig is supplied to the exec provider and is available as the provider's `cluster` attribute.
- When the exec configuration requests cluster information, the cluster information is emitted in the `KUBERNETES_EXEC_INFO` environment variable when the provider runs.
