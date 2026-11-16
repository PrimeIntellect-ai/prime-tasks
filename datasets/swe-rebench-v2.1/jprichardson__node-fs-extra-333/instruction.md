rename `clobber` flags to `overwrite`

### Additional contract requirements

The public copy and move APIs accept an `overwrite` option in place of the historic `clobber` option. Both option names are accepted, and `overwrite` takes precedence when both are supplied.

- `copySync(src, dest, options)` (exported as `fs.copySync`) accepts `options.overwrite` (boolean, default `true`). When `overwrite` is `false` and the destination exists, the copy is skipped; if `options.errorOnExist` is `true`, an error is thrown instead. The legacy `options.clobber` is accepted as an alias when `overwrite` is not supplied.
- `ncp(source, dest, options, callback)` (exported as `ncp`) accepts `options.overwrite` (boolean, default `true`). When `overwrite` is `false`, existing destination files are not replaced; `options.errorOnExist` controls whether an error is reported. The legacy `options.clobber` is used only when `overwrite` is undefined.
- `move(source, dest, options, callback)` (exported as `move`) accepts `options.overwrite` (boolean, default `false`). When `overwrite` is `true`, an existing destination is replaced. The legacy `options.clobber` is accepted as an alias when `overwrite` is not supplied.


- For `move`, when `overwrite` is `false` and the destination exists, the callback receives an error whose `code` is `EEXIST`.
