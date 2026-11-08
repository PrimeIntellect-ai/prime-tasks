use config mounts to attach volumes
Mounts only works with command flag.

### Additional contract requirements

- Loading a configuration file that declares mounts attaches each declared volume, resolving it to its stored volume path and recording it in `RunConfig.Mounts`.
- `BuildImageCommandFlags.MergeToConfig` reports a failure to process mounts by returning a non-nil error.
