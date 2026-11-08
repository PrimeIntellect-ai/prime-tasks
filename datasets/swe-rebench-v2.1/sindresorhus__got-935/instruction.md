Wrapping `RequestError` obscures its source
#### What would you like to discuss?

When I’m working on and with nock, I often see stack traces that look like this:

```
OverriddenClientRequest.request.once.error (node_modules/got/source/request-as-event-emitter.js:178:14)
OverriddenClientRequest.origin.emit.args (node_modules/@szmarczak/http-timer/source/index.js:37:11)
lib/request_overrider.js:24:552
```

Or sometimes:

```
OverriddenClientRequest.request.once.error (/Users/pnm/code/nock/node_modules/got/source/request-as-event-emitter.js:178:14)
OverriddenClientRequest.emit (events.js:187:15)
OverriddenClientRequest.EventEmitter.emit (domain.js:442:20)
OverriddenClientRequest.origin.emit.args (/Users/pnm/code/nock/node_modules/@szmarczak/http-timer/source/index.js:37:11)
/Users/pnm/code/nock/lib/request_overrider.js:24:552
process._tickCallback (internal/process/next_tick.js:61:11)
```

The underlying stack trace is this:

```
end (/Users/pnm/code/nock/lib/request_overrider.js:32:187)
/Users/pnm/code/nock/lib/request_overrider.js:13:2198
OverriddenClientRequest.RequestOverrider.req.write (/Users/pnm/code/nock/lib/request_overrider.js:13:1387)
OverriddenClientRequest.RequestOverrider.req.end (/Users/pnm/code/nock/lib/request_overrider.js:13:1970)
handleRequest (/Users/pnm/code/nock/node_modules/got/source/request-as-event-emitter.js:212:14)
get (/Users/pnm/code/nock/node_modules/got/source/request-as-event-emitter.js:236:5)
Immediate.setImmediate (/Users/pnm/code/nock/node_modules/got/source/request-as-event-emitter.js:307:10)
```

However when got wraps the error in a RequestError, the original stack trace is no longer available.

To be fair, part of what makes this confusing is that the test runner’s output (which has nothing to do with nock or got) and looks like this:

```
 FAIL  tests/test_intercept.js
Nock: No match for request {   "method": "GET",   "url": "http://example.com/",   "headers": {     "user-agent": "got/9.6.0 (https://github.com/sindresorhus/got)",     "accept-encoding": "gzip, deflate"   } }

				} else {
					error = new RequestError(error, options);
-------------^
				}

  stack: >
    OverriddenClientRequest.request.once.error
    (node_modules/got/source/request-as-event-emitter.js:178:14)

    OverriddenClientRequest.origin.emit.args (node_modules/@szmarczak/http-timer/source/index.js:37:11)

    lib/request_overrider.js:24:552
  at:
    line: 178
    column: 14
    file: node_modules/got/source/request-as-event-emitter.js
    function: OverriddenClientRequest.request.once.error
```

For a long time it was unclear that the error and had anything to do with Nock. Nock doesn’t appear in the stack trace despite being the layer that threw the error. And the test runner's output doesn't make it quite so clear to me that “Nock: No match for request” was the message for the error that was being emitted by got.

There is [not much that is documented about RequestError](https://github.com/sindresorhus/got/blob/dfb46ad0bf2427f387968f67ac943476597f0a3b/readme.md#gotrequesterror), though I imagine the benefit of wrapping errors in RequestError is to associate with the thrown error the additional bits information about the request. In this case, however, the wrapping did not provide a benefit. Instead, it made it harder to understand what was happening.

Some possible ideas for making this easier for developers to understand:

1. [HIDDEN] I experimented with this locally and it seems to work. (Though it is slightly disorienting to see Nock’s stack trace attached to something called RequestError, which is not from nock.)
2. Replace the wrapping with decorating. Instead of creating a new error, attach the got-related `options` to the existing error object.
3. Modify nock so it doesn’t emit this error through the request.

I’d be really curious to hear  your thoughts on (1) and (2)! Regardless of what's decided here, I think (3) could be worth pursuing, as it will make it easier both to test nock and also to use it.

I can’t find a discussion on this specific topic, though there was some discussion about async stack traces in #279 and #447.

Thanks so much for all your work on this amazing library!

#### Checklist

- [x] I have read the documentation.

### Additional contract requirements

When Got wraps an underlying request error, its resulting error stack must retain the underlying error’s original stack so the source of the failure remains visible.
