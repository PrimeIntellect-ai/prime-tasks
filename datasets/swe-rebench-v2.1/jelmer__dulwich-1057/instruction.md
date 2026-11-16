Support repository format version 1
Dulwich should implement git repository format version 1.

This is fairly straightforward - it just requires checking the extensions field.

See https://git-scm.com/docs/gitrepository-layout#_version_1

### Additional contract requirements

- When opening a repository with format version 1, inspect its `[extensions]` section. Opening must be rejected by raising `dulwich.repo.UnsupportedExtension` if the section contains an extension that Dulwich does not support, including `worktreeconfig`. The offending extension name must be available in the exception's `.extension` attribute.
