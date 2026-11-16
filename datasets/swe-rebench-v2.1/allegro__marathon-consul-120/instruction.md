Disabling command healthchecks registration
Currently marathon-consul migrates all healthchecks from marathon/mesos to consul. I would like to have a possibility to disable migration for healthchecks type of command.

### Additional contract requirements

- The Consul client configuration exposes a public field `IgnoredHealthChecks string` in the `consul` package's `Config` struct.
- `IgnoredHealthChecks` holds a comma-separated list of Marathon health-check type names that must not be migrated to Consul. Matching is case-insensitive and whitespace surrounding each entry is ignored.
- When `IgnoredHealthChecks` is empty or contains only commas and whitespace, no health checks are ignored.
- A health check whose type matches an ignored entry is omitted from the checks registered for the service; every other health check is migrated as before.
