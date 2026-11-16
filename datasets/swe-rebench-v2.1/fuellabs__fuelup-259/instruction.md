uninstalling a custom toolchain does not re-set a default toolchain
### Problem

As described above in title.

### Steps

Assuming starting with another toolchain already installed,

1. fuelup toolchain new my-toolchain
2. fuelup toolchain uninstall my-toolchain
3. fuelup default

`fuelup default` still shows the uninstalled `my-toolchain` as default.

### Possible Solution(s)

We should default back to the `latest` or `nightly` toolchain if possible in that order, and if they don't exist exist we should switch to the first custom toolchain in alphabetical order.

### Notes

_No response_

### Fuelup version

```console
10.2
```


### Installed components

```console
-
```

### Additional contract requirements

- When the active toolchain is uninstalled, `fuelup` must re-set the default to an available toolchain, preferring `latest`, then `nightly`, and otherwise the first custom toolchain in alphabetical order.
- `fuelup default` with no argument prints the current default toolchain as `<toolchain> (default)`.
