Node v10.13.0 fs.mkdir recursive option not supported
Hey,

It appears there is no support for the seemingly new `fs.mkdir` option `recursive` which recursively builds paths.
```javascript
// Creates /tmp/a/apple, regardless of whether `/tmp` and /tmp/a exist.
fs.mkdir('/tmp/a/apple', { recursive: true }, (err) => {
  if (err) throw err;
});
```
Going by this issues https://github.com/tschaub/mock-fs/issues/254#issuecomment-425573723 I guess this might not be implemented as it's a node v10+ feature?

Thanks 😃

### Additional contract requirements

- `fs.mkdir(path, options, callback)` accepts `options` as either a numeric mode or an object `{recursive?: boolean, mode?: number}`. When `recursive` is `true`, any missing parent directories are created. `mode` sets the permission bits of every directory created by the call. The callback is invoked with `null` on success and with an `Error` on failure.
- `fs.mkdirSync(path, options)` accepts the same `options` shapes and creates any missing parent directories when `recursive` is `true`.
- `Binding.mkdir(pathname, mode, recursive)` in module `lib/binding` creates the directory, and when `recursive` is truthy also creates any missing ancestor directories. `mode` sets the permission bits of every directory created by the call.
- Directory creation that cannot be completed reports an `Error`: `EEXIST` when the target already exists, `ENOENT` when a parent is missing and `recursive` is not enabled, and `EACCES`/`EPERM` when permissions forbid creation.
