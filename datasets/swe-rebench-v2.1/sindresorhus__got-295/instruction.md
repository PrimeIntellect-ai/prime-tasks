Got throws on unsupported protocol
Hey, we've recently started using the latest version of [probe-image-size](https://github.com/nodeca/probe-image-size), which under the hood uses `got`.

Since then, we've seen a bunch of those:

```js
_http_client.js:55
    throw new Error('Protocol "' + protocol + '" not supported. ' +
    ^
2017-05-03T12:32:25.058531056Z
Error: Protocol "c:" not supported. Expected "http:"
    at new ClientRequest (_http_client.js:55:11)
    at Object.exports.request (http.js:31:10)
    at opts (/usr/src/app/node_modules/got/index.js:33:18)
    at ClientRequest.fn.request.res (/usr/src/app/node_modules/got/index.js:51:5)
    at ClientRequest.g (events.js:286:16)
    at emitOne (events.js:96:13)
    at ClientRequest.emit (events.js:188:7)
    at HTTPParser.parserOnIncomingClient [as onIncoming] (_http_client.js:472:21)
    at HTTPParser.parserOnHeadersComplete (_http_common.js:105:23)
    at TLSSocket.socketOnData (_http_client.js:361:20)
    at emitOne (events.js:96:13)
    at TLSSocket.emit (events.js:188:7)
    at readableAddChunk (_stream_readable.js:172:18)
    at TLSSocket.Readable.push (_stream_readable.js:130:10)
    at TLSWrap.onread (net.js:542:20)
```

We're running an application that requires scraping a wide variety of web pages, which in turn contain an even wider variety of images, which we probe using `got`.

While image urls starting with `c:` are not common at all and will likely not resolve to anything helpful, we'd like to not return 5xx errors when such weird images are found on a page, and fail more helpfully instead.

[HIDDEN]

[HIDDEN]

This isn't enough, as such errors are still coming in, which I've identified as coming from redirects, e.g. <https://tinyurl.com/lbf3aq9> is valid itself, but will 301 redirect to the fictitious and invalid `c://users/pioul/Downloads/icon.jpg`, which will throw.

[HIDDEN]

### Additional contract requirements

- `got.UnsupportedProtocolError` is an exported error constructor; instances are subclasses of `Error` (`instanceof Error`).
- The error message is exactly `Unsupported protocol "${opts.protocol}"`, where `opts.protocol` is the offending protocol (for example `c:`).
- A request whose URL protocol is neither `http:` nor `https:` throws this error, including when the unsupported protocol comes from a redirect target.
