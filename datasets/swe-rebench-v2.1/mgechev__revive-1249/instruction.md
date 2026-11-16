error-strings does not allow multiple functions for the same package
**Describe the bug**
[HIDDEN] If the arguments list has multiple functions under the same package like `a.Wrap` and `a.New`, the last function is linted against.

**To Reproduce**
Configure `error-strings` with error functions in the same package. e.g. `errors.New` will overwrite the default map.

**Expected behavior**
Allow multiple functions in the same package to be linted against.
