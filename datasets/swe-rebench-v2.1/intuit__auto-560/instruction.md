Repository missing tags - fatal: No names found, cannot describe anything
**Describe the bug**
If you use auto for a project which has not pushed any tags you get the following misleading error: `fatal: No names found, cannot describe anything.`.

Here's what our build on Circle CI produces:

```
✔  success   Updated body on PR #50
✔  success   Published canary version: 4.8.0-canary.50.390
Error: Running command 'git' failed

fatal: No names found, cannot describe anything.
```

After looking at the code it's due to the [git describe](https://github.com/intuit/auto/blob/d1a11ee91aa80e3e18582059654aa87fa3e098e5/packages/core/src/git.ts#L577).

After googling  I found a stack overflow with a [possible solution](https://stackoverflow.com/questions/4916492/git-describe-fails-with-fatal-no-names-found-cannot-describe-anything).

**To Reproduce**
Use auto with a repository which has never pushed any tags.
