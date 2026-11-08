Nock delay not working when timeout value defined in agent instead of in request itself
### Please avoid duplicates

- [X] I checked [all open bugs](https://github.com/nock/nock.js/issues?q=is%3Aissue+is%3Aopen+label%3Abug) and none of them matched my problem.

### Reproducible test case

https://runkit.com/codinbox/nock-delay

### Nock Version

13.2.2

### Node Version

16.13.0

### TypeScript Version

_No response_

### What happened?

When using nock to test timeout with .delay() function, if request timeout not set but agent timeout, the delay does not work.

If timeout is define in request options, delay() function works and a timeout is triggered.

Nock does not check agent timeout when request timeout does not exist.

### Would you be interested in contributing a fix?

- [X] yes
