handle error formatting on `context.DeadlineExceeded` from hooks using fxevent
When the context exceeds a deadline during `OnStart`, the stack trace is added to the error passed up.
https://github.com/uber-go/fx/blob/fa108cc8a102c5a64d9a08d91d287024e9142507/app.go#L778-L788

If I understand correctly, the linked code is where this wrapping occurs, and the preferred solution is to let fxevent handle the display of the error.

We recently came across this when trying to suppress the stack trace in an error during startup https://github.com/celestiaorg/celestia-node/issues/1458. The stack trace is pretty scary for users, and doesn't appear on other startup errors that don't exceed a context deadline.

### Additional contract requirements

- When a hook exceeds the deadline during `OnStart`, the error returned by `Start` is the underlying context error (`context deadline exceeded`) itself. The hook name and stack trace are not appended to it.
