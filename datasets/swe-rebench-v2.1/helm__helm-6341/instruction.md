Add function to create configuration for actions in pkg
I'm playing around with the v3 beta, and trying to refactor the terraform provider. There doesn't seem to be an easy way to create a configuration, and I feel like I am duplicating a bunch of logic from initActionConfig in cmd/helm. It would be super helpful if there some methods added to build the configuration object in pkg

### Additional contract requirements

Expose `action.InitActionConfig(envSettings *cli.EnvSettings, allNamespaces bool, helmDriver string, log DebugLog) (*Configuration, error)` in package `pkg/action` so callers do not need to duplicate command setup. It must initialize and return an action configuration using the supplied settings, namespace-scope choice, storage driver, and logger, or return an error when initialization fails. A successful result must have its Kubernetes client, REST client getter, and release storage initialized, and must preserve the supplied logger.

Add a public method `Namespace() string` on `EnvSettings` in package `pkg/cli` (import path `helm.sh/helm/v3/pkg/cli`) that returns the effective Kubernetes namespace. An explicitly supplied namespace flag takes precedence over `HELM_NAMESPACE`; when neither supplies a namespace, the namespace configured for the current context in kubeconfig is returned; when none is set or found, return `default`.
