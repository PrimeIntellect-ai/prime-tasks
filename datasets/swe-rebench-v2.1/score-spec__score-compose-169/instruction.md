[FEATURE] support volume subpath
Documentation says:

> Volume mounts with path will be rejected. Docker compose doesn't support sub-path mounts for Docker volumes."

this isn't true (since https://github.com/compose-spec/compose-go/pull/594)
```yaml
      - type: volume
        source: foo
        target: /app
        volume:
          subpath: etc/settings
```

### Additional contract requirements

- The public function `ConvertSpec(state *project.State, spec *score.Workload) (*compose.Project, error)` in package `internal/compose` converts a Score workload into a Docker-Compose project.
- When a container volume references a named volume resource and supplies a non-empty `path`, the generated volume configuration stores that path as the volume's subpath, joined with any subpath already present on the resource output.
- When a container volume references a bind resource and supplies a non-empty `path`, the path is appended to the host source directory of the bind mount.
- When a container volume references a tmpfs resource and supplies a non-empty `path`, the conversion fails with an error whose message contains `can't mount named tmpfs volume with sub path`.
- When the conversion of a container volume fails, the returned error message follows the pattern `containers.<container>.volumes[<idx>]: <detail>`.
- A named volume resource with a non-empty `path` is no longer rejected; it converts successfully as described above.


- When a referenced resource is missing, the error detail must be `resource 'data' does not exist`; when a resource has no `type` output, the error detail must be `resource 'thing.default#test.data' has no 'type' output`.
