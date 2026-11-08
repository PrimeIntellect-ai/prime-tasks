Enable parsing config values in virtual manifests
### Checklist

- [X] I've looked through the [issues and pull requests](https://github.com/cross-rs/cross/issues?q=) for similar request
- [ ] This feature could be solved with a [custom docker image](https://github.com/cross-rs/cross#custom-docker-images) (optional)

### Describe your request

Cross should be able to parse config values from `[workspace.metadata.cross]` sections.

### Describe why this would be a good inclusion for `cross`

It seems to be impossible to set per-workspace config values when using virtual manifests without editing `Cross.toml`, since `[package.metadata]` sections do not work in virtual manifests.

An applicable scenario would be when the `CROSS_CONFIG` variable is set to a global, constant, `Cross.toml` file.
