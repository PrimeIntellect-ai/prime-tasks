Nullable string serialized as double-quoted empty string
### Expected Behavior
As mentionned in the docs (https://github.com/fastify/fast-json-stringify#nullable), properties marked as `nullable: true` should be serialized as `null`.

### Current Behavior
Currently, a null string is serialized as a double-quoted empty string (```""```)

### Steps to Reproduce
```js
const fastJson = require('fast-json-stringify')

let stringify = fastJson({
  type: 'object',
  properties: {
    nullableString: { type: 'string', nullable: true },
  }
})

let data = {
  nullableString: null
}

console.log(stringify(data))

// => {"nullableString":""}
```

### Workaround
Remove `nullable: true`  and mark property type as `['string', 'null']`

### Context (Environment)
- node v11.5.0
- fast-json-stringify v1.11.3
