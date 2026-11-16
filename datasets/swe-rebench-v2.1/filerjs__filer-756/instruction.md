Shell.mkdirp does not support relative paths
exactly as the title says. trying it gives me `(EINVAL): Path must be absolute.`

As a workaround, [HIDDEN] works of course.

### Additional contract requirements

- `Shell.mkdirp` must accept relative paths and interpret them relative to the shell’s current working directory.
