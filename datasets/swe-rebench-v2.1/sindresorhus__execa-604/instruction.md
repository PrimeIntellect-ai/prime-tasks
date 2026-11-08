Add `stdin: Iterable` option
We could allow the `stdin` option to be a sync/async iterable (of strings or byte integers).

This would replace the `input` option, since `stdin: [string]` could be used instead.

Augmenting the `stdin` option instead of having a separate `input` option is more in line with the designs proposed in #591 and #592.

Also, being able to pass any iterable to `stdin` can have multiple use cases. For example, this would allow using a `function *()` generator to pass inputs to a process.

### Additional contract requirements

Each value yielded by a synchronous or asynchronous iterable used as `stdin` must be a string or a `Uint8Array`; individual numeric byte values are not supported.
