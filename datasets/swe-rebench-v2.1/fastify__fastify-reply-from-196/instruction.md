`buildURL` doesn't handle `base` with port 80
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure the bug has not already been reported


### Fastify version

3.21.4

### Plugin version

6.0.1

### Node.js version

14.x

### Operating system

macOS

### Operating system version (i.e. 20.04, 11.3, 10)

11.6

### Description

If `base` contains `:80`, the `buildURL` function throws.

### Steps to Reproduce

```js
const { buildURL } = require('fastify-reply-from/lib/utils')

buildURL('/graphql', 'http://localhost:80')
```

This throws - removing the `:80` works.

(`new URL` strips out the port for `http` URLs (and `443` for `https`))

### Expected Behavior

It should gracefully handle the default port being provided
