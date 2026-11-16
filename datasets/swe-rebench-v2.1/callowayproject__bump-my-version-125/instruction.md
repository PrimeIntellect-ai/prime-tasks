Bumping version adds extra whitespace to `pyproject.toml`
* bump-my-version version: 0.16.1
* Python version: 3.12.1
* Operating System: Ubuntu 22.04 LTS

### Description

The newest version of `bump-my-version` adds an extra newline to the `pyproject.toml` file when bumping the version. This is causing issues for me with linters and code formatting tools.

### What I Did

```
$ bump-my-version bump build
```

### Notes

See line 152 here: https://github.com/Ouranosinc/xclim/commit/a368fa4cbb4f9f6842cceb34d74d1542adb490fb
