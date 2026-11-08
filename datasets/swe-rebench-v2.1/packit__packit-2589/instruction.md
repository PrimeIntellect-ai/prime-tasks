[FR] Expose the spec file path as an environment variable
### Description

It's possible to specify a custom [`specfile_path`]. But there's also hook points where one is expected to fix it + maybe they'd use it again.

I think it should be exposed as an environment variable so it's usable in `create-archive` and other spots. I just identified that it's hardcoded in two places of the config right now.

[`specfile_path`]: https://packit.dev/docs/configuration#specfile_path

### Benefit

Less copy-paste. Also, for people who don't set [`specfile_path`], it'd be a convenient way to make sure they're working with the same file as what Packit auto-detected.

### Importance

Minor annoyance.

### Workaround

- [x] There is an existing workaround that can be used until this feature is implemented.

### Participation

- [ ] I am willing to submit a pull request for this issue. (Packit team is happy to help!)

### Additional contract requirements

- The spec file path is exposed to action hooks as the environment variable `PACKIT_SPECFILE_PATH`. Its value is the package's configured `specfile_path`.
- The package configuration exposes a public method `get_base_env()` that returns a `dict[str, str]` of the environment variables common to all actions, including `PACKIT_CONFIG_PACKAGE_NAME`, `PACKIT_UPSTREAM_PACKAGE_NAME`, `PACKIT_DOWNSTREAM_PACKAGE_NAME` and `PACKIT_SPECFILE_PATH`.
