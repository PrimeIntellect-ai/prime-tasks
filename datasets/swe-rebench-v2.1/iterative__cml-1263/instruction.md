pr without arguments
Users should be allowed to manually `git commit` a few times before running `cml pr create` (not `cml pr create .`)

Since #1275 isn't released yet it means there's no way whatsoever to use `cml pr`

(from #1181 and https://github.com/iterative/cml/pull/1277#issuecomment-1339920209)

### Additional contract requirements

- The `cml pr create` command accepts an optional list of glob paths, so its usage signature is `cml pr create [glob path...]`.
