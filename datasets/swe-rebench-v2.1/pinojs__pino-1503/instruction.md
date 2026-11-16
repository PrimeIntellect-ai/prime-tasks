v8.3.0 throws "SonicBoom supports only file descriptors and files"
After upgrading from 8.2.0 to 8.3.0 my very basic usage of `pino` is now throwing:

```
Error: SonicBoom supports only file descriptors and files
 ❯ new SonicBoom node_modules/sonic-boom/index.js:121:11
 ❯ buildSafeSonicBoom node_modules/pino/lib/tools.js:214:18
 ❯ normalizeArgs node_modules/pino/lib/tools.js:308:18
 ❯ Proxy.pino node_modules/pino/pino.js:84:28
```

My code is:

```js
import pino from 'pino';
const logger = pino();
export default logger;
```

Rolling back to 8.2.0 makes the problem go away. I looked at the diff between 8.2.0 and 8.3.0 and I can't figure out what's wrong. Could something in the `sonic-boom` package upgrade be causing this?
