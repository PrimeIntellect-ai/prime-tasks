OnBoot implementation is broken
### Steps to reproduce

Setting the onboot network parameter to false will still set this flag in the templates as
```
{{- if $netdev.OnBoot }}
```
will always evaluate to true, regardless what ` $netdev.OnBoot` contains!

### Error message

_No response_

### Information on your system

Failing in tests in #1753

### General information

- [x] I have run `wwctl version` and reported the contents of `/etc/os-release`
- [x] I have searched the issues of this repo and believe this is not a duplicate
- [x] I have captured and reported relevant error messages and logs

### Additional contract requirements

- The `WWbool` type in package `github.com/warewulf/warewulf/internal/pkg/wwtype` must provide a method `BoolDefaultTrue() bool`. It converts the underlying string to a boolean, returning true for true-like values and defaulting to true when the value is empty.
- The debug overlay must render a network device's OnBoot entry as `OnBoot: <value> (<default-true value>)`, so a true OnBoot value appears as `OnBoot: true (true)`.
