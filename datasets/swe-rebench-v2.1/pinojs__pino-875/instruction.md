TypeError: Cannot read property 'labels' of undefined
```js
//test.js
const pino = require('pino')();

process.on('warning', (warning) => {
  pino.info(warning);
});
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})
process.on('foo', () => {});
process.on('foo', () => {})

```


  [HIDDEN]
               ^

TypeError: Cannot read property 'labels' of undefined

### Additional contract requirements

When a Pino logger is registered to log process warnings, triggering a warning by registering repeated listeners must not cause warning logging to throw a TypeError.
