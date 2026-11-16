1.3.98 swc minify breaks property name with non-ascii char when asciiOnly is on
### Describe the bug

when asciiOnly is on, swc minify emits invalid property name which is original unicode.

works fine with 1.3.97 but 1.3.98

### Input code

```typescript
const a = {aób: 'ó'}

console.log(a)
```


### Config

```json
{
  "jsc": {
    "parser": {
      "syntax": "ecmascript",
      "jsx": false
    },
    "target": "es5",
    "loose": false,
    "minify": {
      "compress": true,
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

https://play.swc.rs/?version=1.3.98&code=H4sIAAAAAAAAA0vOzysuUUhUsFWoTjy8OclKQf3wZvVaLq5koHh%2BTqpeTn66RqImAJ8BdbomAAAA&config=H4sIAAAAAAAAA02PMQ7DIAxF95wi8ty1HXqHqmdA1KmIICDbkYqi3L0OgSSLZb%2F%2FjT9L1%2FcwsoVnv2irQzLESMeshPMk5qcE0AbDllwSuDV15E0ajGcsaN0VEENflLLF92oHHyNjs1cW3OSGfD1oY0iEzMqEZjxODZGCkYtTmeZx7j35XM1VWbtWSx4I8TN7PH8pOeGe7QGnqSU54oHjV9ssr69%2FIxZbWDEBAAA%3D

### SWC Info output

_No response_

### Expected behavior

```js
console.log({
    "a\xf3b": "\xf3"
});
```


### Actual behavior

```js
console.log({
    a\xf3b: "\xf3"
});
```


### Version

1.3.98

### Additional context

_No response_
