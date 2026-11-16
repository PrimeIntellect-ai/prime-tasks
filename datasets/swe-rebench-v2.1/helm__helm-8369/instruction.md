Environment variable for max release history
Environment variable for setting the max history for an environment. This would remove need to set it on each upgrade with the `--history-max` flag. Similar to `TILLER_HISTORY_MAX` variable in Helm 2.

Output of `helm version`:
Helm 3

### Additional contract requirements

- The environment variable is named `HELM_MAX_HISTORY`.
- The configured value is exposed as the public field `MaxHistory` (an `int`) on `EnvSettings` in package `helm.sh/helm/v3/pkg/cli`.
- When `HELM_MAX_HISTORY` is unset, empty, or not a valid integer, `MaxHistory` is `10`.
- When an upgrade is run without `--history-max`, its default limit is the value configured by `HELM_MAX_HISTORY`.
