`asciiOnly: true` results in invalid escape code inside identifier
### Describe the bug

`asciiOnly: true` results in invalid escape code inside identifier

### Input code

```typescript
const módulo = 123;
console.log(módulo);
```


### Config

```json
{
  "jsc": {
    "parser": {
      "syntax": "ecmascript",
      "jsx": false
    },
    "target": "es3",
    "loose": false,
        "minify": {
            "compress": false,
            "format": {
                "asciiOnly": true
            }
        }
  },
  "module": {
    "type": "es6"
  },
  "minify": false,
  "isModule": true
}
```


### Playground link (or link to the minimal reproduction)

https://play.swc.rs/?version=1.4.14-nightly-20240411.1&code=H4sIAAAAAAAAA0vOzysuUcg9vDmlNCdfwVbB0MjYmisZKJifk6qXk5%2BuAZXStAYATd5jRSoAAAA%3D&config=H4sIAAAAAAAAA2VQSwqDQAzde4oh6%2B4KXfQO0jMM01hG5kcSoSLevePoqMVd8j55j0yNUtCzgaea8piXpImR9j0jPAbR34wAGq%2FZkE0Ct8r2vFCddowFmlcGRNMHpbj4vsnBxchY5fVExr0NthtPoRtuok%2BEzFdLobtIXsvFVrhc1NpXcMtVoQH%2FFHNznkpl8PE9ODweIWPCtf4DDlEtutcBy211lpz5B8lC%2FqlUAQAA

### SWC Info output

_No response_

### Expected behavior

Output valid JS

### Actual behavior

Invalid JS:
```js
var m\xf3dulo = 123;
console.log(m\xf3dulo);
```

### Version

1.4.14-nightly-20240411.1

### Additional context

Coming from https://github.com/parcel-bundler/parcel/issues/9632

### Additional contract requirements

- For the supplied input and configuration, emit exactly:
```js
var m\u00f3dulo = 123;
console.log(m\u00f3dulo);
```
- When `asciiOnly` is enabled, non-ASCII characters in identifiers are escaped with `\u` escapes; characters in the range U+007F–U+00FF use lowercase hexadecimal digits (for example `µ` becomes `\u00b5`), and characters above U+00FF use uppercase hexadecimal digits (for example `σ` becomes `\u03C3`).
