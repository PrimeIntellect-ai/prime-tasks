Allow --exact flag for `shipit` to ensure no `^` on releases
**Is your feature request related to a problem? Please describe.**

Currently, `shipit` calls Lerna to version the monorepo, but does not pass in the `--exact` flag. My team uses Renovate bot to keep our dependencies exact, so this means I will get a PR on every release to align shared dependencies in the monorepo

**Describe the solution you'd like**

A way to pass a `--exact` flag to `shipit` that goes straight to `Lerna` so that I can guarantee the updated versions will be committed without `^`

### Additional contract requirements

- The npm plugin configuration must support an `exact` option. When enabled, `shipit` must pass Lerna's `--exact` flag while versioning the monorepo so updated dependency versions are committed without `^`.
