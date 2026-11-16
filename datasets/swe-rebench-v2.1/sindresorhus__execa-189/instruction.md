Make it cancelable
Using: https://github.com/sindresorhus/p-cancelable

It's possible to call `cp.kill()`, but would be nicer if it was cancelable.

### Additional contract requirements

- The object returned by `execa()` exposes a `cancel()` method that takes no arguments. Calling it kills the spawned subprocess (so `spawned.killed` becomes `true`) and causes the promise returned by `execa()` to reject with an error whose `isCanceled` property is `true`.
- Calling `cancel()` on a subprocess that has already been killed or already canceled is a no-op.
- A resolved result object returned by awaiting `execa()` has `isCanceled` set to `false`. Cancellation causes the promise to reject, so it does not produce a resolved result with `isCanceled` set to `true`.
- The error object rejected by the promise returned from `execa()` has an `isCanceled` property that is `true` when the rejection is caused by a call to `cancel()`, and `false` for other error conditions (such as being killed via `kill()`, a non-zero exit code, or a timeout).
