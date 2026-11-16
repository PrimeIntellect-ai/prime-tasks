custom toolchain: creating a new toolchain should set it as default
`fuelup toolchain new my-toolchain` should instantly set `my-toolchain` as the default toolchain, since its likely the dev would want to continue acting upon the newly created toolchain.

### Additional contract requirements

- For `fuelup toolchain new my-toolchain`, stdout must be exactly `New toolchain initialized: my-toolchain\ndefault toolchain set to 'my-toolchain'\n`.
