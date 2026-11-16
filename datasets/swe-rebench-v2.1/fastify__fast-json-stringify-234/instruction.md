Mandatory items for type array
# 🐛 Bug Report

For types `array` the `items` key is not mandatory by the standard, but it is needed by fast-json-stringify.
We should set a default instead

## To Reproduce

```js
var fastJsonStringify = require("fast-json-stringify")
const str = fastJsonStringify({
  "type": "object",
  "properties": {
    "foo": {
      "type": "array"
       // , items: { type: 'string' } // uncomment to let it works
    }
  }
})
```

## Expected behavior

The type of the item's array should be `any`

## Your Environment

- *node version*: 10
- *jast-json-stringify*: 1.16.1
- *os*: Windows 10
