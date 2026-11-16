`RangeError: Invalid array length` when `data` is set to a large `Buffer`
### Describe the bug

Axios throws `RangeError: Invalid array length` when `data` is set to a large `Buffer`

## Explanation

When axios merges configurations, it checks for empty objects:

[HIDDEN]

Calling `Object.keys` on a `Buffer` instance will try to enumerate every byte as a key. Node.js decides to die when there are more than 100-200 million keys (100-200MB byte length).

## Workaround

```ts
import axios from 'axios'

main()

async function main() {
    const buffer = Buffer.alloc(1024 * 1024 * 200) // 200 MB buffer
    const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength)
    await axios({
        method: 'POST',
        url: 'http://localhost:1633/bzz',
        data: arrayBuffer
    })
}
```

Passing `ArrayBuffer` instead of `Buffer` solves the issue, but it is not ideal as it requires additional conversion.

### To Reproduce

```ts
import axios from 'axios'

main()

async function main() {
    const buffer = Buffer.alloc(1024 * 1024 * 200) // 200 MB buffer
    await axios({
        method: 'POST',
        url: 'http://localhost:8080',
        data: buffer
    })
}
```

Output:

```
~/node_modules/axios/lib/utils.js:134
  return val && Object.keys(val).length === 0 && Object.getPrototypeOf(val) === Object.prototype;
                       ^

RangeError: Invalid array length
    at Function.keys (<anonymous>)
    at Object.isEmptyObject (~/node_modules/axios/lib/utils.js:134:24)
    at getMergedValue (~/node_modules/axios/lib/core/mergeConfig.js:21:22)
    at valueFromConfig2 (~/node_modules/axios/lib/core/mergeConfig.js:43:14)
    at computeConfigValue (~/node_modules/axios/lib/core/mergeConfig.js:98:23)
    at Object.forEach (~/node_modules/axios/lib/utils.js:281:10)
    at mergeConfig (~/node_modules/axios/lib/core/mergeConfig.js:96:9)
    at Axios.request (~/node_modules/axios/lib/core/Axios.js:41:12)
    at wrap (~/node_modules/axios/lib/helpers/bind.js:5:15)
    at main (~/src/axios.ts:7:11)

Node.js v20.18.3
```

### Code snippet

```js

```

### Expected behavior

Since `Buffer` is common, e.g. the default return types of `readFile` or `readFileSync` are Buffers, naively trying to upload a large file in Node.js will trigger this error.

When `typeof Buffer !== 'undefined'`, `axios` should detect and work with it properly during configuration merging.

### Axios Version

0.30.0

### Adapter Version

Node.js default

### Browser

_No response_

### Browser Version

_No response_

### Node.js Version

v20.18.3

### OS

MacOS Sonoma 14.6.1

### Additional Library Versions

```bash

```

### Additional context/Screenshots

```bash

```

### Additional contract requirements

- `utils.isEmptyObject(value)` must return `false` for `Buffer` instances without throwing, so that configuration merging handles `Buffer` values safely.
