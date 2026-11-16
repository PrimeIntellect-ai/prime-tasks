msg property is not logged when first arg is undefined
In node.js (tested in 14 and 16), logs do not contain the `msg` property when the first parameter is `undefined`.

The following code
```
const logger = require("pino")();

logger.info("hello world");
logger.info({ a: 1 }, "hello world");
logger.info(null, "hello world");
logger.info(undefined, "hello world");

const child = logger.child({ a: "im a child" });
child.info({ a: 1 }, "hello daddy");
child.info(null, "hello daddy");
child.info(undefined, "hello daddy");
```

logs the following content (hostname has been changed 😉 ):

```
{"level":30,"time":1663063554791,"pid":43360,"hostname":"...","msg":"hello world"}
{"level":30,"time":1663063554791,"pid":43360,"hostname":"...","a":1,"msg":"hello world"}
{"level":30,"time":1663063554791,"pid":43360,"hostname":"...","msg":"hello world"}
{"level":30,"time":1663063554791,"pid":43360,"hostname":"..."}
{"level":30,"time":1663063554791,"pid":43360,"hostname":"...","a":"im a child","a":1,"msg":"hello daddy"}
{"level":30,"time":1663063554791,"pid":43360,"hostname":"...","a":"im a child","msg":"hello daddy"}
{"level":30,"time":1663063554791,"pid":43360,"hostname":"...","a":"im a child"}
```

We can see the 4th log of both main logger and child logger does not have a `msg` property whereas it is ok when the first parameter is `null`.

However, it seems to be ok in the browser.
Tested here : https://codesandbox.io/s/js-playground-forked-qsnm99?file=/src/index.js
