Allow filtering non-deprecated versions from yaml and json output
Currently, the show-all flag doesn't affect the yaml or json output. This should probably be the case.

### Additional contract requirements

- When the show-all flag is not enabled, the `json` and `yaml` output formats must include only deprecated versions (non-deprecated versions are filtered out).
- When the show-all flag is enabled, the `json` and `yaml` output formats must include all versions.
- The `json` and `yaml` serialization format (field names and structure) is unchanged from the existing behavior.
