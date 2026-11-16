Git walker ignores any files which don't have the mode 100644
**Describe the bug**

This causes executable files (like shellscripts) to not get formatted.

**To Reproduce**

Steps to reproduce the behavior:

1. Create a shell script which is formatted according to shfmt, make it executable
2. Add config for shfmt in treefmt.toml
3. Run treefmt

**Expected behavior**

The shellscript is formatted according to shfmt

**System information**

treefmt v2.0.4
OS: Linux

**Additional context**

These lines seem to be ignoring too much:
https://github.com/numtide/treefmt/blob/1427cc2d98d5270f5720e5edac1f34e10c602876/walk/git.go#L54-L57

[HIDDEN]

### Additional contract requirements

- In Git-walk mode, executable regular files selected by a formatter must be available for formatting; their executable bit alone must not cause them to be skipped.
