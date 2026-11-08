`chan struct{}` triggers nested-structs error
**Describe the bug**
`chan struct{}` triggers the nested-structs error.

**Expected behavior**
I expected this use case to be ignored.

**Desktop (please complete the following information):**
 - OS: macOS Monterey
 - Version of Go: 1.19

**Additional context**
I'm presuming this is a false positive bug and there's no idiomatic go way to work around it (apologies if there is and I wasn't aware).
