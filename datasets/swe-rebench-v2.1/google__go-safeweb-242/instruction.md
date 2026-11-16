All registered paths call the same handler
Buggy place: https://github.com/google/go-safeweb/blob/0c2edce93f20a51c77af2057b966ab5530e2114e/safehttp/mux.go#L75.

The closure passed to `mux.HandleFunc` [HIDDEN], making [HIDDEN]. Oops.

### Additional contract requirements

- A request to a registered path must invoke the handler registered for that path.
