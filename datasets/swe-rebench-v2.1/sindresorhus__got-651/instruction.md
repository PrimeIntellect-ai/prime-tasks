Socket hang up for stream put
I get a socket hang up when creating a read stream and then piping it to a put stream.
```
events.js:183
      throw er; // Unhandled 'error' event
      ^

RequestError: socket hang up
    at ClientRequest.request.once.error (/mnt/c/Users/marti/mvp-rest/node_modules/got/source/request-as-event-emitter.js:175:19)
    at Object.onceWrapper (events.js:315:30)
    at emitOne (events.js:121:20)
    at ClientRequest.emit (events.js:211:7)
    at ClientRequest.origin.emit.args [as emit] (/mnt/c/Users/marti/mvp-rest/node_modules/@szmarczak/http-timer/source/index.js:36:11)
    at Socket.socketOnEnd (_http_client.js:423:9)
    at emitNone (events.js:111:20)
    at Socket.emit (events.js:208:7)
    at endReadableNT (_stream_readable.js:1064:12)
    at _combinedTickCallback (internal/process/next_tick.js:139:11)
```

If i use request library instead for put then it works.

Code to reproduce:
```js
var got = require('got')
var request = require('request')
require('http')
  .createServer((req, res) => {
    if (req.method === 'GET') {
      console.log('getting')
      res.end('get')
    } else {
      console.log(req.method)
      res.end('put/post/etc ok')
    }
  })
  .listen(3100, () => {
    got.stream.get('http://localhost:3100').pipe(got.stream.put('http://localhost:3100'))
    // got.stream.get('http://localhost:3100').pipe(request.put('http://localhost:3100'))
  })
```

[HIDDEN]

Not saying removing that is a fix, but it seems got or node have a problem with that header being set, or being set to a certain value. Not sure what request sets it to.

Setting header content-length to 0 or some other incorrect values "fixes" it. But request manages to read correct content-length of the incoming stream. Would be nice if got did the same.

### Additional contract requirements

- Piping a readable stream into `got.stream.put(url)` must complete successfully as an HTTP `PUT` request and deliver the readable stream's data unchanged.
