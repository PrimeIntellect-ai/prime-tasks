Print currently in-use toolchain if no arguments are provided to `use`
To retrieve the currently in-use toolchain, users currently need to either visually parse the output of `swiftly list` or pipe it to `grep use`. To make this a bit easier, swiftly should print the in use toolchain if no arguments are provided to `use`.

e.g.
```
$ swiftly use
main-snapshot-2023-09-22 (in use)
```
