`pino.final` without a handler and `stream.flushSync()`
I discovered that pino.final can be used without a handler, which I find very handy. Example:

```js
const handler = (err) => {
  const finalLogger = pino.final(logger);

  if (err) finalLogger(err);
  process.exit(err ? 1 : 0);
};
```

But reading the code I found something that might be a bug and perhaps someone here can confirm it.

https://github.com/pinojs/pino/blob/c57c25855d89a2c481914672bbdeebe7ec3087c7/lib/tools.js#L463-L478

`stream.flushSync()` is only called before the handler is executed or after `finalLogger` is used. In the example above there is no handler and `finalLogger` is only called if there is an error, so when the process exits normally there is no call to `stream.flushSync()`.

Perhaps the implemention when there is no handler should be this

```js
  [HIDDEN]
```

### Additional contract requirements

- When `pino.final` is called without a handler, it must synchronously flush its stream before returning, even if the returned final logger is never invoked.
- If that flush throws, the error must not escape from `pino.final`.
