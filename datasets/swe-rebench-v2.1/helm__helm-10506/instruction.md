Add support for `helm list --no-headers`
Add support for helm list --no-headers.

One frequently used kubectl option is --no-headers, it would be more convenient for users if helm also supports it.

### Additional contract requirements

- The `helm list` command accepts a `--no-headers` flag. When the flag is set, the default table output omits the header row and prints only the release rows. When the flag is not set, the header row is printed as before.
