TypeError: appender is not a function
The order in which the appenders are defined seems _very_ important. This gives some strange results:

This sample:

```ts
const log4js = require('log4js');
log4js.configure({
  appenders: {
     filteredConsole: { type: 'logLevelFilter', appender: 'console', level: 'info' },
     console: { type: 'stdout' }
  },
  categories: {
    default: { appenders: ['filteredConsole'], level: 'trace' }
  }
});
log4js.getLogger('demo').info('test');
```

Results in error: `TypeError: appender is not a function`.

[HIDDEN]
