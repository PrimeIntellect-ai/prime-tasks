allow custom environment variables for any execution unit
today we only pass back environment variables for lambda. Assuming that we can do this uniform for all exec unit types we should add this to generic config (not pulumi params) and then write these env vars as core.EnvironmentVariables so its reusable across platforms and IaCs

### Additional contract requirements

- Custom environment variables can be attached to any execution unit, regardless of its type (for example `lambda` or `fargate`).
- Variables are declared per execution unit in the generic execution unit configuration, under the key `environment_variables` as a map from variable name to value. They are not Pulumi-specific parameters (`pulumi_params`).
- Each configured variable appears in the execution unit's environment variables as a core environment variable with the same name and value.
