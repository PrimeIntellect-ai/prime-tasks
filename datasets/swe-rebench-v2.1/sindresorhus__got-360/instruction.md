Cannot cancel when timeout option is set
When the options.timeout, or options.timeout.request, is set, [HIDDEN] This prevents the possibility of calling cancel.

See [index.js#L130-L132](https://github.com/sindresorhus/got/blob/master/index.js#L130-L132).

Is this intentional?

### Additional contract requirements

- The exported function `got(url, options)` in `index.js` returns a promise for the HTTP response. The returned promise also exposes a `.cancel()` method.
- Calling `.cancel()` aborts the in-progress request and rejects the returned promise with `PCancelable.CancelError`.
- `options.timeout` accepts either a number of milliseconds or an object with a `request` field giving the request timeout in milliseconds.
- Calling `.cancel()` must continue to abort an in-progress request and reject the returned promise with `PCancelable.CancelError` when `options.timeout` is set as either a number or an object with a `request` field.
