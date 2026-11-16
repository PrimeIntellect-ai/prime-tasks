`forc deploy` binary not found when fuel-toolchain.toml is present
### Problem

When inside a directory with a fuel-toolchain.toml ([example](https://github.com/sarahschwartz/sway-farm/tree/main/contract)), `fuel deploy --help` executes the `forc` executable rather than `forc-deploy`

If I use the full path to the executable, i.e. `$HOME/.fuelup/toolchains/beta-3-aarch64-apple-darwin/bin/forc-deploy --help`, it executes `forc-deploy` correctly. However, if I use `$HOME/.fuelup/bin/forc-deploy --help`, it does not work.

### Steps

If I use the full path to the executable, i.e. `$HOME/.fuelup/toolchains/beta-3-aarch64-apple-darwin/bin/forc-deploy --help`, it executes `forc-deploy` correctly. However, if I use `$HOME/.fuelup/bin/forc-deploy --help`, it does not work.

### Possible Solution(s)

_No response_

### Notes

_No response_

### Fuelup version

```console
fuelup 0.18.1
```


### Installed components

```console
beta-3-aarch64-apple-darwin
  forc - Up to date : 0.35.5
  fuel-core - Up to date : 0.17.4
  fuel-indexer - Up to date : 0.6.0
fuelup - Up to date : 0.18.1
```

### Additional contract requirements

- The command written as `fuel deploy --help` in the issue is the `forc` proxy invoked with the `deploy` subcommand (`forc deploy --help`). With a `fuel-toolchain.toml` present, it must execute the `forc-deploy` executable, not `forc`.
- Invoking the linked `forc-deploy` binary directly (e.g. `$HOME/.fuelup/bin/forc-deploy --help`) must execute `forc-deploy` as well.
