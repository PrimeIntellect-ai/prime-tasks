delayBody doesn't work with abort signal (nock@14.0.0-beta.16)
### Please avoid duplicates

- [X] I checked [all open bugs](https://github.com/nock/nock/issues?q=is%3Aissue+is%3Aopen+label%3Abug) and none of them matched my problem.

### Reproducible test case

https://gist.github.com/sam-super/1706b4e46a92a9d3ec64a13ee7c7d3ca

### Nock Version

14.0.0-beta.16

### Node Version

v22.11.0

### TypeScript Version

_No response_

### What happened?

Unlike nock v13 (with node-fetch package) `delayBody` doesn't work correctly with `14.0.0-beta.16` using node's native fetch.

[this gist](https://gist.github.com/sam-super/1706b4e46a92a9d3ec64a13ee7c7d3ca) compares using nock vs spinning up a nodejs server to delay the response body. if you run it you should get this:

```text
node version: v22.11.0
 ---------- node test ----------
response received after 0.01s
NODE: Correctly threw error after timeout: TimeoutError: The operation was aborted due to timeout
 ---------- /node test ---------
 ---------- nock test ----------
response received after 0.008s
body received after 1.209s
NOCK: BUG - got a successful response in spite of setting AbortSignal.timeout(1000) and response delay of 1200: NockResBody
 ---------- /nock test ---------
 ```
in case it helps `delayConnection` works in `14.0.0-beta.16` (however in 14.0.0-beta.7 `delayConnection` didn't work).

### Would you be interested in contributing a fix?

- [X] yes
