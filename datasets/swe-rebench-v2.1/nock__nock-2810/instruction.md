Nock beta does not handle gzip responses properly
### Please avoid duplicates

- [X] I checked [all open bugs](https://github.com/nock/nock/issues?q=is%3Aissue+is%3Aopen+label%3Abug) and none of them matched my problem.

### Reproducible test case

https://github.com/holzerch/nock-gzip-test-case

### Nock Version

nock@14.0.0-beta.16

### Node Version

v22.11.0

### TypeScript Version

5.6.3

### What happened?

In case the recorded content of a HTTP response is gzipped, it cannot be replayed and produces the following error.
```
TypeError:
        at handleKnownInternalErrors (node:internal/webstreams/adapters:115:21)
        at Gunzip.<anonymous> (node:internal/webstreams/adapters:476:13)
        at Gunzip.<anonymous> (node:internal/util:543:20)
        at Gunzip.onerror (node:internal/streams/end-of-stream:136:14)
        at Gunzip.emit (node:events:530:35)
        at emitErrorNT (node:internal/streams/destroy:170:8)
        at emitErrorCloseNT (node:internal/streams/destroy:129:3)
        at processTicksAndRejections (node:internal/process/task_queues:90:21) {
      code: 'Z_DATA_ERROR',
      [cause]: Error: incorrect header check
          at genericNodeError (node:internal/errors:983:15)
          at wrappedFn (node:internal/errors:537:14)
          at Zlib.zlibOnError [as onerror] (node:zlib:185:17)
          at Zlib.callbackTrampoline (node:internal/async_hooks:130:17) {
        errno: -3,
        code: 'Z_DATA_ERROR'
      }
    }
```
Please see the attached repo for further details

### Would you be interested in contributing a fix?

- [ ] yes

### Additional contract requirements

When HTTP responses are recorded and later replayed, a recorded response whose
`content-encoding` header names any of the following must be replayable, and
replaying it must yield the original uncompressed response body while retaining
the recorded `content-encoding` header:

- `gzip`
- `deflate`
- `br` (Brotli)
- stacked encodings that combine multiple codings, for example `gzip, br`
