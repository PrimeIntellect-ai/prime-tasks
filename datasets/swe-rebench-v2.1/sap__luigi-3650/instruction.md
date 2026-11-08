container: add possibility to configure feature policies and sandbox rules
For iframe based micro frontends.
See https://docs.luigi-project.io/docs/general-settings/?section=allowrules and https://docs.luigi-project.io/docs/general-settings/?section=customsandboxrules in luigi-core.

### Additional contract requirements

On `luigi-container`, users can configure iframe policies with `allow-rules` and `sandbox-rules` attributes whose values are JSON-encoded arrays of strings. The rendered iframe must reflect the configured feature-policy rules in its `allow` policy and the configured sandbox tokens in its `sandbox` policy; configuration must not be limited to fixed policy values.
