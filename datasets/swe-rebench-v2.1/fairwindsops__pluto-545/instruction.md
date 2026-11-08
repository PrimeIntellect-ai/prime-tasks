Add a "--kubeconfig" global flag
**Is your feature request related to a problem? Please describe.**
I often work with multiple clusters. In my case, each has a separate kubeconfig file.
Often this is because clusters are spun up for testing using e.g. vagrant+Ansible.

Having to export `KUBECONFIG=...` each time I need to target a different cluster is error prone and tedious.

**Describe the solution you'd like**
Other tools, including kubectl and helm, allow using a `--kubeconfig` global flag, that uses the file given as argument to this flag as the kubeconfig for the command.

**Describe alternatives you've considered**
- exporting `KUBECONFIG=...`
- using things like kubie etc.

### Additional contract requirements

- Add a public function `GetConfig(kubeContext string, kubeConfigPath string) (*rest.Config, error)` in package `pkg/kube`. It returns a Kubernetes REST configuration for the given context. When `kubeConfigPath` is non-empty, the kubeconfig file at that path is used; when it is empty, the default kubeconfig discovery is used. It returns a non-nil error when the configuration cannot be loaded, for example when the context does not exist or the kubeconfig file is invalid.
- The `--kubeconfig` flag is accepted by the commands that connect to a Kubernetes cluster, including `detect-helm`, and the file given to the flag is used as the kubeconfig for that command, taking precedence over the `KUBECONFIG` environment variable.


- When `detect-helm` is run with `--kubeconfig` set to a kubeconfig whose server address is `127.0.0.1:54753`, the command output must contain the literal `127.0.0.1:54753`.
