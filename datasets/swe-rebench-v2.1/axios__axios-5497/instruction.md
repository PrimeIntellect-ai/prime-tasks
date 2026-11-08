Deflate fails on server response without zlib header
<!-- Click "Preview" for a more readable version --

Please read and follow the instructions before submitting an issue:

- Read all our documentation, especially the [README](https://github.com/axios/axios/blob/master/README.md). It may contain information that helps you solve your issue.
- Ensure your issue isn't already [reported](https://github.com/axios/axios/issues?utf8=%E2%9C%93&q=is%3Aissue).
- If you aren't sure that the issue is caused by Axios or you just need help, please use [Stack Overflow](https://stackoverflow.com/questions/tagged/axios) or [our chat](https://gitter.im/mzabriskie/axios).
- If you're reporting a bug, ensure it isn't already fixed in the latest Axios version.
- Don't remove any title of the issue template, or it will be treated as invalid by the bot.

⚠️👆 Feel free to these instructions before submitting the issue 👆⚠️
-->

#### Describe the bug
Some servers are not sending a zlib header in their deflated data. CURL had the same problem and implemented a "fix" for it: https://github.com/curl/curl/blob/5c932f8fe9dad94a7417702958ffa9e8db67c549/lib/content_encoding.c#L227-L229

Axios is also returning a `Z_DATA_ERROR` in this case.

#### To Reproduce

Use axios to request a page without a zlib header in the deflated data (e.g. https://www.konicaminolta.eu/eu-en/about-us/corporate-book) and force it to only accept deflate encoding.

```js
let url = 'https://www.konicaminolta.eu/eu-en/about-us/corporate-book';
let config = {
  headers: { 'Accept-Encoding': 'deflate' }
};

await axios.get(url, config);
```

#### Expected behavior

Getting the correctly inflated data.

#### Environment
 - Axios Version [0.21.1]


#### Additional context/Screenshots
