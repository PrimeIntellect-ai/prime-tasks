Wrong http status assigned to status.FailedPrecondition
**Describe the bug**
`status.InvalidArgument` and `status.FailedPrecondition` are different statuses but are mapped to the same `http.StatusBadRequest`:

https://github.com/swaggest/rest/blob/master/error.go#L130
https://github.com/swaggest/usecase/blob/master/status/status.go#L97

**Expected behavior**
`status.FailedPrecondition`  should be mapped to `http.StatusPreconditionFailed`.

**Additional context**
Related: #145
