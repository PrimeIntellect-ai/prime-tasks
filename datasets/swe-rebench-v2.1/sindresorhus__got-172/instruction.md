ParseError on response with no body
I'm using `got` to query a JSON API where some endpoints simply return `200` with no body.

`got` throws a [`ParseError`](https://github.com/sindresorhus/got/blob/3dc219e70474e54c4ec4b2c27468f6ff722f8c6b/index.js#L107) because it only skips parsing if the status code is `204`.

I wonder if it makes sense to skip parsing every time the body is empty, without checking the status code.

```js
[HIDDEN]
```

I'm happy to send a pull request if you think the above change would be useful.
