Pino logger mutate (pollute) my input objects with logging information (immutability)
I'm using pino as logger. Everything was fine util i discovered that pino mutate my object injecting "logging" properties.

Here here a snippet

```
const logger = require('pino')()

let useful_object = {test: true}
logger.info(useful_object, "my logging information)

console.log(useful_object)

//{"level":30,"time":1554358981834,"pid":27753,"hostname":"mother","test":true,"msg":"my logging information","v":1}
//{ test: true, msg: 'my logging information' }
```

(check that useful_object now has the msg property)

There is a way to configure pino to use immutable objects instead append properties to them? Or i have to clone my objects?

```js
// create an object copy before logging
logger.info({...useful_object}, "my logging information")
```

*That object pollution is worst when i integrate pino in express.js with `express-pino-logger` where a lot of properties are attached to it*

### Additional contract requirements

- When metadata is observed for a call that logs an object with a message, the observed object must not contain an automatically added `msg` property: logging `{ hello: 'world' }` with `'a msg'` leaves the observed object as `{ hello: 'world' }`, and the equivalent child-logger observation is `{ from: 'child' }`.
