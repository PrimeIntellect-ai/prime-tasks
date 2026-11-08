Bug: level prop in browser doesn't work
http://getpino.io/#/docs/API?id=level

Changing minimum logging level doesn't work as described in the documentation.

```
const pino = require("pino")({
  level: "info"
});

pino.info("display. OK");
pino.trace("doens't display. OK");

pino.level = "trace";
pino.trace("doens't display. ERROR");
```

pino version:  4.16.1

### Additional contract requirements

- The browser logger is the module exported by the package's browser entry point (`browser.js`, i.e. `require('pino/browser')`).
- `pino(opts)` creates a browser logger. `opts` is optional and may contain `level` (a level name string) and `browser.write` (a function that receives each emitted log object).
- The logger exposes the logging methods `fatal`, `error`, `warn`, `info`, `debug` and `trace`.
- The logger exposes a `level` property. Reading it returns the current level name. Assigning one of the known level names (`fatal`, `error`, `warn`, `info`, `debug`, `trace`, `silent`) changes the minimum logging level and immediately enables or disables the logging methods accordingly. Assigning any other string throws `Error('unknown level ' + level)`. Setting the level to `silent` disables all logging.
- The logger exposes a read-only `levelVal` property; assigning to it throws. It returns the numeric severity of the current level.
- `pino.levels.values` maps level names to their numeric severity: `fatal` 60, `error` 50, `warn` 40, `info` 30, `debug` 20, `trace` 10.
- `pino.levels.labels` maps numeric severities back to level names: `60` to `fatal`, `50` to `error`, `40` to `warn`, `30` to `info`, `20` to `debug`, `10` to `trace`.


- The enumerable keys of `pino.levels.values` are exactly `fatal`, `error`, `warn`, `info`, `debug`, and `trace`; `silent` is not a key.
- For a logging call with only a message argument and no bindings, the object delivered to `browser.write` has exactly the properties `level`, `msg`, and `time`. `level` is the numeric severity, `msg` is the supplied message, and `time` is no greater than `Date.now()` when the callback runs.
