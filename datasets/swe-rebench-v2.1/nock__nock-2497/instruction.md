nock.removeInterceptor can remove the wrong Intercept
### Please avoid duplicates

- [X] I checked [all open bugs](https://github.com/nock/nock.js/issues?q=is%3Aissue+is%3Aopen+label%3Abug) and none of them matched my problem.

### Reproducible test case

https://codesandbox.io/p/sandbox/sad-bessie-5rrf15?file=%2Findex.js&selection=%5B%7B%22endColumn%22%3A1%2C%22endLineNumber%22%3A9%2C%22startColumn%22%3A1%2C%22startLineNumber%22%3A9%7D%5D&workspace=%257B%2522activeFileId%2522%253A%2522cl8ool9vg0000lqg683en1egb%2522%252C%2522openFiles%2522%253A%255B%2522%252FREADME.md%2522%252C%2522%252Findex.js%2522%255D%252C%2522sidebarPanel%2522%253A%2522EXPLORER%2522%252C%2522gitSidebarPanel%2522%253A%2522COMMIT%2522%252C%2522sidekickItems%2522%253A%255B%257B%2522type%2522%253A%2522TASK_LOG%2522%252C%2522taskId%2522%253A%2522yarn%2520add%2520nock%2522%252C%2522key%2522%253A%2522clakeepbd00vg3b6hgq6eguo2%2522%252C%2522isMinimized%2522%253Afalse%257D%252C%257B%2522type%2522%253A%2522TASK_LOG%2522%252C%2522taskId%2522%253A%2522start%2522%252C%2522key%2522%253A%2522claked0xa000n3b6hy9fop8v3%2522%252C%2522isMinimized%2522%253Afalse%257D%255D%257D

### Nock Version

13.2.9

### Node Version

16.17.0

### TypeScript Version

_No response_

### What happened?

`nock.removeIntercept` searches for a "matching nock" even when provided the exact nock that needs to be removed.  The search algorithm is inadequate such that it can remove the wrong nock if there are multiple nocks on the same root uri with different query parameters.

```
const nock = require("nock");
const assert = require("assert");

const searchScope = nock("http://fakeSearch.com");
const puppyNockIntercept = searchScope.get("/search?q=puppies");
puppyNockIntercept.reply(200, { puppies: [] });
const kittenNockIntercept = searchScope.get("/search?q=kittens");
kittenNockIntercept.reply(200, { kittens: [] });

nock.removeInterceptor(kittenNockIntercept);

const remainingNocks =
  searchScope.keyedInterceptors["GET http://fakesearch.com:80/search"];

assert(remainingNocks.length === 1, "Only 1 nock remains");

const remainingNock = remainingNocks[0];

assert(
  remainingNock.uri === "/search?q=kittens",
  "The puppies nock was removed instead of kittens"
);
```

### Would you be interested in contributing a fix?

- [ ] yes
