bunyan patching fails with Error: No target object provided.
**Describe the bug**
During loading, an error is returned:

```
/Users/admin/project/node_modules/dd-trace/packages/datadog-shimmer/src/shimmer.js:108
    throw new Error('No target object provided.')
          ^

Error: No target object provided.
    at assertMethod (/Users/admin/project/node_modules/dd-trace/packages/datadog-shimmer/src/shimmer.js:108:11)
    at wrapMethod (/Users/admin/project/node_modules/dd-trace/packages/datadog-shimmer/src/shimmer.js:35:3)
    at Object.wrap (/Users/admin/project/node_modules/dd-trace/packages/datadog-shimmer/src/shimmer.js:65:7)
    at /Users/admin/project/node_modules/dd-trace/packages/datadog-instrumentations/src/bunyan.js:11:11
    at cjsPostLoad (/Users/admin/project/node_modules/dd-trace/packages/datadog-instrumentations/src/helpers/instrument.js:84:5)
    at addHook (/Users/admin/project/node_modules/dd-trace/packages/datadog-instrumentations/src/helpers/instrument.js:33:3)
    at Object.<anonymous> (/Users/admin/project/node_modules/dd-trace/packages/datadog-instrumentations/src/bunyan.js:9:1)
    at Module._compile (internal/modules/cjs/loader.js:1085:14)
    at Object.Module._extensions..js (internal/modules/cjs/loader.js:1114:10)
    at Module.load (internal/modules/cjs/loader.js:950:32)
```

**Environment**

* **Operation system:**
* * MacOs Monterey & node:14-alpine docker container
* **Node version:**
* * v14.19.0
* **Tracer version:**
* * "^2.4.0"
* **Agent version:**
* * 7

**Index.js**
```
import tracer from 'dd-trace';
tracer.init({service: 'myservice', plugins: true, logInjection: true});
import bunyan from 'bunyan';

const logger = bunyan.createLogger({
  name: 'myservice-logger',
  stream: process.stdout,
})
```

**package.json**
```
  "name": "myservice",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "type": "module"
  "dependencies": {
    "bunyan": "^1.8.15",
    "dd-trace": "^2.4.0"
  },
...
```

### Additional contract requirements

- The instrumentation hook mechanism must not fail when a CommonJS module is loaded through ESM interception. In that case the module namespace exposes the CommonJS exports under a `default` property, and the registered instrumentation callback must receive those CommonJS exports (the `default` value) rather than the namespace wrapper. This is what allows the described bunyan application to load without throwing `No target object provided`.
