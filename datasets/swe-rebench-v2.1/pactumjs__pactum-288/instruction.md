Capture cookies as res.cookies in stores and returns
**Is your feature request related to a problem? Please describe.**
Capture cookies as `res.cookies` in `stores` and `returns`

**Describe the solution you'd like**
```js
stores('TOKEN', 'res.cookies.token')
```

### Additional contract requirements

- The `returns` selector must also support `req.cookies` (for example, `req.cookies.token`).
