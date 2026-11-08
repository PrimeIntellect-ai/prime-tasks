URI malformed when trying to get URL with URL-encoded chars
Hello,

Catched URI malformed error in new "got", when I trying to send request to URL with URL-encoded chars.
URL examples:
https://www.kinopoisk.ru/community/city/%D2%E0%EB%EB%E8%ED/
https://www.kinopoisk.ru/news/keyword/%C7%E2%E5%E7%E4%ED%FB%E5+%E2%EE%E9%ED%FB/

nodejs: 9.2.0
got: 8.0.0

Failed code:
```js
const got = require('got');

(async () => {
	try {
		const response = await got('https://www.kinopoisk.ru/community/city/%D2%E0%EB%EB%E8%ED/');
		console.log(response);
	} catch (error) {
		console.log(error);
	}
})();
```
```
URIError: URI malformed
    at decodeURI (<anonymous>)
    at module.exports (/Users/kirill-m/git/test/node_modules/normalize-url/index.js:87:21)
    at /Users/kirill-m/git/test/node_modules/cacheable-request/src/index.js:43:16
    at get (/Users/kirill-m/git/test/node_modules/got/index.js:98:20)
    at Promise.resolve.then.size (/Users/kirill-m/git/test/node_modules/got/index.js:274:5)
    at <anonymous>
```

Broken at this commit: https://github.com/sindresorhus/got/commit/3c7920507fae88a5f53d0640b5116fa34a5ed829

Any ideas?

### Additional contract requirements

- If a string URL contains percent-encoded bytes that are not valid UTF-8 character sequences, reject it with an error whose message includes the text "Parameter `url` must contain valid UTF-8 character sequences".
- A string URL containing well-formed UTF-8 percent-encoded characters remains usable.
