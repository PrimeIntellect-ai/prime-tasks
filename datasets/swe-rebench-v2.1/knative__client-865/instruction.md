Support `--ce-override` on `ping` and `apiserver` sources
### Feature request

All `Source`-ducktyped objects include a `CloudEventOverride`, which serializes as `extensions`. In `kn`, this is exposed as an option for `source binding create` and `source binding update`, but not for comparable commands on `ping` and `apiserver` command groups.

Also print the cloud event overrides extensions in `describe` output for sources if present.

The request is to add identical support to these other sources for consistency.

### Additional contract requirements

- In ping source `describe` output, include the label `Overrides` when CloudEvent extensions are present.
