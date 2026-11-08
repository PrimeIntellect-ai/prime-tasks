edit user doesn't provide a way to set data or sub limits

### Additional contract requirements

- The `nsc edit user` command must accept `--subs` to set the user's subscription limit and `--data` to set the user's data limit; `--subs 100` sets the limit to 100 and `--data 1K` sets the limit to 1024 bytes.
