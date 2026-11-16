Reuse existing destructuring assignments when extracting member expressions
Given

```javascript
function test(obj) {
  return obj.x + obj.y * obj.x + obj.y
}
```

`obj.x` and `obj.y` are repeated, so let's extract both of them, replacing all occurrences. The end result is as follows.

```javascript
function test(obj) {
  const { x } = obj
  const { y } = obj
  return x + y * x + y
}
```

The second extraction could have reused the destructuring assignment that the first extraction created, making the code one line shorter.

```javascript
function test(obj) {
  const { x, y } = obj
  return x + y * x + y
}
```

- Version of the extension used: _v4.7.0_
