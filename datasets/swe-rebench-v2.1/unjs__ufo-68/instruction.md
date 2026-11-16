override urls with protocol with `withBase`
Reference: https://github.com/unjs/ohmyfetch/pull/113

Current behavior:

```js
// http://base/http://domain
ufo.withBase('http://domain', 'http://base')
```

New behavior:

```js
// http://domain
ufo.withBase('http://domain', 'http://base'})
```

URL behavior:

```js
// http://domain/
new URL('http://domain', 'http://base').toString()
```
