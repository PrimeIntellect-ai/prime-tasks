Quadratic number of interceptors reported by activeMocks
### Please avoid duplicates

- [X] I checked [all open bugs](https://github.com/nock/nock.js/issues?q=is%3Aissue+is%3Aopen+label%3Abug) and none of them matched my problem.

### Reproducible test case

See example snippet in description.

### Nock Version

13.2.4

### Node Version

16.13.1

### TypeScript Version

_No response_

### What happened?

When registering multiple interceptors in the same scope, calling `nock.activeMocks()` reports too many active mocks: all those interceptors are present `n^2` times. For instance, registering 5 interceptors in a scope will result in 25 mocks reported by `nock.activeMocks()`.

```
const nock = require('nock')
const scope = nock('http://example.com')
  .get('/').reply(200)
  .get('/other').reply(200)
  .get('/third').reply(201)
console.log(nock.activeMocks())
```
Expected logged:
```
[
  'GET http://example.com:80/',
  'GET http://example.com:80/other',
  'GET http://example.com:80/third',
]
```
Actual:
```
[
  'GET http://example.com:80/',
  'GET http://example.com:80/other',
  'GET http://example.com:80/third',
  'GET http://example.com:80/',
  'GET http://example.com:80/other',
  'GET http://example.com:80/third',
  'GET http://example.com:80/',
  'GET http://example.com:80/other',
  'GET http://example.com:80/third'
]
```

Note: this appears to have been reported in the past, but the Issue was closed due to staleness: https://github.com/nock/nock/issues/600. That Issue mentioned the same problem for `nock.pendingMocks()`, which, I guess, has the same root cause.


### Would you be interested in contributing a fix?

- [x] yes
