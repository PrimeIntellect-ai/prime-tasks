Potential data race on sys.FS when context cancelation enabled.
Hitting a race condition that I don't quite understand.  Made a reproducible test for it here:

https://github.com/abraithwaite/wazero/commit/ca10894d


**Environment (please complete the relevant information):**
- Go version: 1.20
- wazero Version: tested v1.0.1 and 8a9d3f28
- Host architecture: arm64 (darwin) and amd64 (github runners)
- Runtime mode: Compiler

Not sure if the way we're using wazero is crazy, so please feel free to comment on that if you think this is improper usage of the library. 🙇‍♂️

### Additional contract requirements

The following public methods on `ModuleInstance` (package `github.com/tetratelabs/wazero/internal/wasm`) must behave as described:

- `Close(ctx context.Context) error` closes the module, records exit code 0, and releases its resources. It is safe to call multiple times.
- `CloseWithExitCode(ctx context.Context, exitCode uint32) error` closes the module, records the supplied exit code, and releases its resources. It is safe to call multiple times.
- `CloseModuleOnCanceledOrTimeout(ctx context.Context) func()` starts a watcher that closes the module when `ctx` is canceled or its deadline is exceeded, and returns a function that stops the watcher.
- `FailIfClosed() error` returns an exit error if the module was closed, and nil otherwise.

When `CloseModuleOnCanceledOrTimeout` closes the module because `ctx` was canceled or its deadline was exceeded, the module's resources (including its system context and any files it has open) must not be released at that point. They must remain pending until `FailIfClosed` is called, at which point `FailIfClosed` releases them and returns the exit error for the cancellation or deadline.


- For cancellation, `FailIfClosed()` returns an error with the exact message `module closed with context canceled`; for deadline expiration, it returns an error with the exact message `module closed with context deadline exceeded`.
- When the open-file lifecycle is exercised with a file at descriptor `3`, that file remains available until `FailIfClosed()` and is unavailable afterward.
