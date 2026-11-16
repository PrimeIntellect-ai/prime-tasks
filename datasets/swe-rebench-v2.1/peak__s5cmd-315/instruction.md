disable wildcard and use "*" as literal?
The S3 objects I'm going to download has "\*" in object key. When I use `cp` to download, `s5cmd` expands it and download multiple objects more than the particular object. Is there a way to escape wildcard "\*" or disable wildcard? Thanks.

### Additional contract requirements

- The `cp` command accepts a boolean flag named `raw` (usable as `--raw` or `-raw`). When it is set, wildcard/glob characters in the source and destination arguments are treated as literal characters and are not expanded.
- Without the flag, the existing wildcard expansion behavior is unchanged.
