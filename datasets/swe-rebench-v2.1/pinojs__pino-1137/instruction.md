pino 7 - error on flush
I get this error:

```
^C/Users/mspigolon/workspace/_experiments/fastify-scripts/node_modules/thread-stream/index.js:307
      cb()
      ^

TypeError: cb is not a function
    at /Users/mspigolon/workspace/_experiments/fastify-scripts/node_modules/thread-stream/index.js:307:7
    at wait (/Users/mspigolon/workspace/_experiments/fastify-scripts/node_modules/thread-stream/lib/wait.js:9:5)
```

For this script:

```
const pino = require('pino')

const transport = pino.transport({
  target: require('path').join(__dirname, './tran.js')
})
const logger = pino(transport)

setInterval(() => {
  logger.info('hello world')
}, 1000)

process.on('SIGINT', () => { logger.flush() })
```

`tran.js` file (from transport documentation):
```js
const { Writable } = require( 'stream')
module.exports = (options) => {
  const myTransportStream = new Writable({
    write (chunk, enc, cb) {
    // apply a transform and send to stdout
    console.log(chunk.toString().toUpperCase())
    cb()
    }
  })
  return myTransportStream
}
```

Or this transport produces the same error:

```js
const build = require('pino-abstract-transport')

module.exports = function (opts) {
  return build(function (source) {
    source.on('data', function (obj) {
      console.log(obj)
    })
  })
}
```

It seems related to this module:
https://github.com/pinojs/thread-stream
