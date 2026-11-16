Log exec.LookPath errors
The error returned by `exec.LookPath` is never surfaced to the user.  Without that detail, the user can't tell the difference between a non-existent path and a permissions issue.  We should log the underlying error message.

**However**, the existing logic tries to lookup the `h.ExecuteCommand` and, upon failure, attempts `filepath.Join(h.CommandWorkingDirectory, h.ExecuteCommand)`.  It can be hard to tell which one the user intended to execute and which error message to show.  We need to update this logic to be more predictable.

My a proposed replacement logic is below.  The primary difference is that if the ExecCmd is an absolute path, webhook won't try prepending the CWD.  This may break some setups, but it makes path lookups more explicit and consistent.  Thoughts, @adnanh?

```go
[HIDDEN]
// ...
```

Related to #456

### Additional contract requirements

When a command is not an absolute path and a command working directory is configured, resolve the command within that working directory rather than first searching for the bare command on PATH.
