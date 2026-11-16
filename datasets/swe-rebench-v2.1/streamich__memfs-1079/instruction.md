Relative symlinks are created relative to the current directory
This is a minor inconsistency with Node.js. According to [their docs](https://nodejs.org/api/fs.html#fs_fs_symlink_target_path_type_callback):
> Relative targets are relative to the link’s parent directory.

Take a look:
```js
const MemFs = require('memfs');
const fs = MemFs.Volume.fromJSON({
    '/test/target': 'foo',
    '/test/folder': null
});

// create symlink
// here memfs resolves '../target' relative to cwd, not '/test/folder'
fs.symlinkSync('../target', '/test/folder/link');

// Error: ENOENT: no such file or directory, open '/test/folder/link'
fs.readFileSync('/test/folder/link');
```
```js
const fs = require('fs');

// create symlink
fs.symlinkSync('../target', 'test/folder/link');

// ok!
fs.readFileSync('test/folder/link');
```

(For your convenience, I've created the [test repo](https://github.com/turikhay/memfs-relative-symlinks))

### Additional contract requirements

- Reading a symlink that was created with a relative target yields that same relative target: `readlinkSync` returns the relative target string that was passed to `symlinkSync`.
