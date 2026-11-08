Add shell completion for OCI feature
The new OCI commands and charts should have shell completion when possible.

### Additional contract requirements

- Shell completion for the `push` command offers local-file completion for its chart-file argument, and does not offer local-file completion for its remote registry-location argument.
- Shell completion for the `registry login` and `registry logout` commands does not offer local-file completion for the registry host argument.
- Shell completion for commands that accept chart references recognizes OCI chart locations, offering the `oci://` prefix among the completions.
