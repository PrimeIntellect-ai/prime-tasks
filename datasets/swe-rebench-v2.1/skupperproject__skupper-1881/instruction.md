V2 move nonkube platform file to internal path
**Is your feature request related to a problem? Please describe.**
No

**Describe the solution you'd like**
Non-kube sites create a platform.yaml file under `runtime/`, as this is currently
just an internal detail, move it to ìnternal/` directory.

**Additional context**
At this point the platform is just used internally, so it is safer to keep it as an internal
implementation detail for now.

### Additional contract requirements

- `pkg/nonkube/api` must export `InternalBasePath` as an `InternalPath` constant with value `"internal"`.
- Non-kube platform configuration is stored at `internal/platform.yaml`. Non-kube code that creates, loads, installs, or removes a site must use this location for the platform file.
