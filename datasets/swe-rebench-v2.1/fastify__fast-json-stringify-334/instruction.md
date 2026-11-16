Integer properties are always stringified as 0
### Prerequisites

- [X] I have written a descriptive issue title
- [X] I have searched existing issues to ensure it has not already been reported


### Fastify version

3.x

### Plugin version

2.7.5

### Node.js version

14.x

### Operating system

macOS

### Operating system version (i.e. 20.04, 11.3, 10)

11.3

### Description

Version 2.7.5 introduced a bug where an integer property always ends up being stringified even if the schema doesn't provide a default value for it.

### Steps to Reproduce

```
const fastJson = require('fast-json-stringify')
const stringify = fastJson({
  title: 'Example Schema',
  type: 'object',
  properties: {
    age: {
      type: 'integer'
    }
  }
})

console.log(stringify({}))
```

### Expected Behavior

I'd expect an empty object as string: `{}` but I get `{ age: 0 }` instead.

Version 2.7.4 and prior ones work as expected.
