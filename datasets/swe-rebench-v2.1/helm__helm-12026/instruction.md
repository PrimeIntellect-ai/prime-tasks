Add TOML parsing capability
Currently, the standard library includes functions to parse data from [JSON and YAML](https://github.com/helm/helm/blob/main/pkg/engine/funcs.go#L50-L56), but there is no built-in function to parse data from [TOML](https://toml.io/).

Given that TOML is sometimes used as format for configuration files (e.g. [GitLab Runner configuration](https://docs.gitlab.com/runner/install/kubernetes.html#additional-configuration)), it would be beneficial to have a `fromToml` function in the standard library, like `fromJson` and `fromYaml`, to provide consistency for developers.

Example use case:
We want to deploy GitLab runners with helm and want to use Googles config-connector to create necessary GCS buckets for caching.
The bucket name therefore needs to be provided twice: in the config-connector resource and in the GitLab config TOML.
To keep the config DRY, we want to be able to extract the GCS bucket name from GitLab's TOML configuration. This is not possible without parsing the TOML configuration.
Other solutions such as YAML anchors or reusing values in the same `values.yaml` file won't work either.

PS: I have a PR in the making. Just adding this issue to adhere to the contribution guidelines.
