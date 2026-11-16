`treefmt` ignores files which are untracked but not gitignored
**Describe the bug**

If you have a file which is not yet tracked by git, but which is not gitignored, then `treefmt` does not format it (because it doesn't show up in `git ls-files`).

[HIDDEN]

**To Reproduce**

Steps to reproduce the behavior:

1. Add a new file
2. Don't `git add` it
3. Run `treefmt`

**Expected behavior**

I would expect it to be formatted.
