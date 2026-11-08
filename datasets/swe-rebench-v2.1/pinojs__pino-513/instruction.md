Options are ignored when logging to a file
Some pino options are ignored when the destination is a file. Also, `useLevelLabels` seems to be able to change after a logger is already created.

Repro code:

```js
const pino = require('pino')

const opts = {
  base: null,
  timestamp: () => ',"time":"none"',
  useLevelLabels: true
}
const logger = pino(opts, './my.log')

logger.info('first')
pino(opts).info('second') // stdout
logger.info('third')
```

Contents of `my.log`:

```json
{"level":30,"time":1535948917084,"msg":"first","pid":34728,"hostname":"ubuntu","v":1}
{"level":"info","time":1535948917085,"msg":"third","pid":34728,"hostname":"ubuntu","v":1}
```

Terminal output:

```json
{"level":"info","time":"none","msg":"second","v":1}
```

Notice how the `base` and `timestamp` options have no effect on the logger that writes to `./my.log`.
Also notice how `useLevelLabels` is ignored at first, but then works after the second logger is created that writes to `stdout`.

Pino: v5.4.0
Node: v10.9.0
OS: Ubuntu 18.04, Windows 10
