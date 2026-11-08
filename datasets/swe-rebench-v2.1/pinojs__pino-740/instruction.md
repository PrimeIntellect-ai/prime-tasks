"EAGAIN: resource temporarily unavailable, write" on fatal
Before https://github.com/pinojs/pino/pull/730, the use of `fatal` was safe.
After that version, my application crash with `EAGAIN: resource temporarily unavailable, write`.

The linked lines live in sonicboom repo:

https://github.com/mcollina/sonic-boom/blob/e1b31fb93c5a8c306cdc16021e81b4995056a5aa/index.js#L245-L248

This behaviour was considered a patch but the behaviour changes.

Can I may send a PR with a patch (maybe a configuration flag)?

### Additional contract requirements

- `pino(stream)` accepts a writable destination stream and returns a logger whose `fatal(...)` method writes a log entry at the fatal level.
- When the destination stream provides a `flushSync()` method, `fatal()` invokes it and suppresses any error it throws, so a failing `flushSync()` never makes `fatal()` throw.
- When `flushSync()` is present, `fatal()` does not invoke the stream's asynchronous `flush()` method, even if `flushSync()` throws.
