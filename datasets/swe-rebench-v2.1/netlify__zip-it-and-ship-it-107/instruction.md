Symlinks in Functions do not always work
Symlinks in Functions do not always work due to two reasons:
  - Zipping does not always keep them as symlinks. Instead we should archive the symlink target file, not the symlink itself.
  - When there is no `package.json`, the absolute path is used to target files inside the zip archive. `resolve()` resolves symlinks with `realpath`, but this creates issues with absolute paths not having the same root directory.
