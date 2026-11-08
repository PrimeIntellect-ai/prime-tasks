Merge set cookie value for same name multiple times
### Environment

Nuxt 3.10.3 with Nitro 2.9.1
Node 20.10.0

### Reproduction

```js
setCookie(e, 'session', '123', { httpOnly: true })
// ...
setCookie(e, 'session', '123', { httpOnly: true, maxAge: /* 1m */ 60 * 60 * 24 * 30 })
```



### Describe the bug

will actually set cookie twice:
```http
set-cookie: session=123; Path=/; HttpOnly
set-cookie: session=123; Max-Age=2592000; Path=/; HttpOnly
```


### Additional context

_No response_

### Logs

_No response_
