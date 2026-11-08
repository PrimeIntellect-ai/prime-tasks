rounding not working in properties
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure it has not already been reported


### Fastify version

3.x

### Node.js version

14

### Operating system

Windows

### Operating system version (i.e. 20.04, 11.3, 10)

10

### Description

The `rounding` options does not apply on properties `integer`s

### Steps to Reproduce

```js
const fastJson = require('fast-json-stringify')
const stringify = fastJson({ type: 'object', properties: { magic: { type: 'integer' } } }, { rounding: 'ceil' })

console.log(stringify({magic: 4.2}))
// should show "5"
```

### Expected Behavior

should show "5"

The issue is on this code block
https://github.com/fastify/fast-json-stringify/blob/2cc2b8a83679688127f97b6ef1fc0e327e5914fb/index.js#L728

[HIDDEN]
