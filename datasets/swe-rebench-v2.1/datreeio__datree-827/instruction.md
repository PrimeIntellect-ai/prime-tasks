support not-strict mode for schema validation
**Is your feature request related to a problem? Please describe.**
today, I can't add  additional properties to my K8s objects because it will fail the schema step ([example](https://github.com/Azure/ip-masq-agent-v2/blob/master/examples/ip-masq-agent.yaml))

**Describe the solution you'd like**
a flag to pass the CLI to use none strict schema for the schema validation step

**Describe alternatives you've considered**
n/a

**Additional context**
By default, kubeconform runs in a none strict mode. We pass the `--strict` flag to force the strict mode in every schema validation check.

### Additional contract requirements

- The `datree test` command accepts a boolean flag `--permissive-schema` (default `false`) that enables non-strict schema validation.
- `K8sValidator.InitClient(k8sVersion string, ignoreMissingSchemas bool, schemaLocations []string, permissiveSchema bool)` in package `bl/validation` initializes the schema validation client. When `permissiveSchema` is `true`, schema validation must accept Kubernetes resources that contain additional (undocumented) properties; when it is `false`, such resources must be reported as invalid.
