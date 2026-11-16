BUG: fs.readdir fails when passing options
The following code:
```javascript
fs.readdir('/somedir', {/* options */}, callback);
```
Throws the error:
`
Error: Uncaught TypeError: callback is not a function (http://localhost:1234/tests.e31bb0bc.js:17740)
    at commonjsGlobal.onerror (mocha.947ba722.js:32655:12)
`

According to the [node documentation](https://nodejs.org/api/fs.html#fs_fs_readdir_path_options_callback), fs.readdir and fs.promises.readdir should optionally accept an options object.

### Additional contract requirements

- `fs.readdir(path, [options], callback)` accepts an optional `options` argument that may be an encoding string (for example `"buffer"`) or an object with optional `encoding` (string) and `withFileTypes` (boolean) properties. The callback receives `(error, entries)`.
- When `options` is the string `"buffer"` (or an object with `encoding: "buffer"`), each entry name is returned as a `Buffer`.
- When `options` is an encoding string other than `"buffer"` (for example `"hex"`), each entry name is returned as a string encoded with that encoding.
- When `options.withFileTypes` is `true`, the callback receives an array of `Dirent` objects. Each `Dirent` has a `name` property and the methods `isFile()`, `isDirectory()` and `isSymbolicLink()`.
- `fs.promises.readdir(path, [options])` accepts the same optional `options` argument and resolves with the same entries.
