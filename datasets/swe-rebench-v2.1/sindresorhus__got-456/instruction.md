Problem with default `Accept-Encoding` header
Why Got adds a default `Accept-Encoding` header ([this line](https://github.com/sindresorhus/got/blob/master/index.js#L475)) even with disabled `decompress` option?

**My scenario:** In my current project I wanted to forward some client request headers from one server to another and header values must be equal in both servers, but when `Accept-Encoding` header is not set, Got adds this header with a default value and that is a problem in this scenario.

I can't find a way to send a request with no `accept-encoding` header,  I had to set an empty string in `accept-encoding` to get around this:

```js
app.use(ctx => {
  const headers = ctx.headers; // client request headers

  got(url, {
    headers: {
      ...headers,
      // Prevent got from adding default accept-encoding header
      'accept-encoding': headers['accept-encoding'] || ''
    }
  })
})
```
`null` and `undefined` not working because in v8.0.0 it will be deleted and then default header will be added.

**My suggestion:** Only set default `accept-encoding` when `decompress` option is enabled, then the following code will work for my scenario:

```js
got(url, {
  decompress: false,
  headers
})
```

I can send a PR, but first I wanted to ask that is there any specific reason to set default `accept-encoding` other than `decompress` option?
