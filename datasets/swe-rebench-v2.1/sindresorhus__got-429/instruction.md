Uncaught TypeError: Cannot read property 'once' of undefined     at EventEmitter.ee.once.req
I'm attempting to use `got` from the browser with `browserify`. Looking through the issues I see others have had success, but I'm currently getting an error when using it. My request completes with the correct respsonse but an error come with it.

```
Uncaught TypeError: Cannot read property 'once' of undefined
    at EventEmitter.ee.once.req (bundle.js:10705)
    at EventEmitter.g (bundle.js:7590)
    at EventEmitter.emit (bundle.js:7521)
    at setImmediate (bundle.js:10740)
    at onNextTick (bundle.js:9657)
    at Item.run (bundle.js:8030)
    at drainQueue (bundle.js:8000)
```

The code is a fairly simple example.
```index.js
const got = require('got')
global.setImmediate = require('timers').setImmediate

const options = {
        method: 'GET'
}

got('https://api.github.com', options)
        .then(x => console.log(x.body))
        .catch(console.log)
```
I'm running this command to make my `bundle.js` file
```
browserify index.js > bundle.js
```

Have I done something incorrectly?

### Additional contract requirements

Using Got from a browserified bundle, a request that receives a successful response must complete without an uncaught TypeError when the request object does not expose a `connection` property.
