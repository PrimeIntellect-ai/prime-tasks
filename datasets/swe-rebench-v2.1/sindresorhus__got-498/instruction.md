Redirection to a malformed URI crashes whole process
Demo:
```javascript
const got = require('got');

(async function() {
    try {
        var response = await got('http://shorturl.at/dsDT8'); // redirects to https://google.com/%D8
    } catch (e) {
        console.log('caught:', e);
    }

    console.log('it should display this');
})();
```

Result:
```bash
$ node blah
/home/szymon/Desktop/server/node_modules/normalize-url/index.js:85
                urlObj.pathname = decodeURI(urlObj.pathname);
                                  ^

URIError: URI malformed
    at decodeURI (<anonymous>)
    at module.exports (/home/szymon/Desktop/server/node_modules/normalize-url/index.js:85:21)
    at /home/szymon/Desktop/server/node_modules/cacheable-request/src/index.js:43:16
    at get (/home/szymon/Desktop/server/node_modules/got/index.js:98:20)
    at res (/home/szymon/Desktop/server/node_modules/got/index.js:140:5)
    at ClientRequest.handler (/home/szymon/Desktop/server/node_modules/cacheable-request/src/index.js:88:7)
    at Object.onceWrapper (events.js:275:13)
    at ClientRequest.emit (events.js:182:13)
    at HTTPParser.parserOnIncomingClient [as onIncoming] (_http_client.js:534:21)
    at HTTPParser.parserOnHeadersComplete (_http_common.js:109:17)
```

There are two possible solutions:
~1. Support malformed URIs.~
2. Throw an error.

~I would recommend the first solution, because you're able to visit `https://google.com/%D8` in browser, even more: you can make a request to that using `http`/`https` module!~

~Because that's upstream issue, I suggest adding a new option: `throwsOnMalformedURI` which is `true` by default.~

EDIT: the first solution would cause too many problems. It should throw a Got error.

### Additional contract requirements

- When a redirect target is a malformed URI, the returned promise rejects with an error whose `name` is `URIError`.
