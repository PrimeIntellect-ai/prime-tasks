Step failure output mangled
**Describe the bug**

If a step fails because the step function returned an error, the output is mangled with `fmt.SPrintf()` error output.

For example, say the step is `And 2 items posted`.  If the function returns `fmt.Errorf("expected %d items, received %d", n, actual)`, then the output would be

> gobdd.go:377: And %!(EXTRA string=2 items posted, *errors.errorString=expected 2 items posted, received 0)

**Expected behavior**

Prints out the step and the error clearly formatted. Something like:

> gobdd.go:377: And 2 items posted: expected 2 items posted, received 0
