Including `msg` in object and string leads to silent data loss
To reproduce:

```
const pino = require('pino')();
pino.info({"msg":"OBJ"},"STRING")
```

The result is that "STRING" is logged and "OBJ" is silently discarded.

This could happen when you use `pino.info(obj)` on an object that happens to have a `msg` property.

The recommended fix when `msg` appears in the object and the string is to throw an error. The current behavior is silent data loss.

There's nothing worse than going to check your logs for some critical detail about a past event only to find it was silently discarded by your logging library and you can't retroactively fix it. If you've got an object that contains a msg property that you want to log, instead of:

    log.info(obj)

You can do:

    log.info({obj}).

The error thrown for the duplicate `msg` case could explain that.
