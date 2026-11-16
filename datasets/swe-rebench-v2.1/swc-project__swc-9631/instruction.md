Correctness - Division plus block comment is turned into line comment
### Describe the bug

When a division operator is followed by a block comment, the result must have a whitespace between them, otherwise it becomes a line comment.

```js
// original
a / /**/ b
// current behavior
a//**/b
// what it should look like
a/ /**/b
```

### Input code

```typescript
console.log(1 / /* @__PURE__ */something())
```


### Config

```json
{
  "jsc": {
    "externalHelpers": true,
    "parser": {
      "tsx": false,
      "syntax": "typescript",
    },
    "preserveAllComments": true,
    "target": "es5"
  },
  "minify": true,
}
```


### Playground link (or link to the minimal reproduction)

https://play.swc.rs/?version=1.7.28&code=H4sIAAAAAAAAA0vOzyvOz0nVy8lP1zBU0FfQ11JwiI8PCA1yjY9X0NIvzs9NLcnIzEvX0NQEAG54Sh4rAAAA&config=H4sIAAAAAAAAA12NPQ7CMAyF954i8tyVhQ2x9BpR9YqCnBDZBjWqendctXRg8%2Fvx95YuBHrqSNew%2BOkCs0FK5AFcIeqByRv9HtYoCjnL7pjOLqfIenTc01YsbjZZq9BRUjXa0%2FUHEjjogxvz%2FZUziv0tWZQHbGNAL9Qdn5RTSVM7q%2BsXeXWPCsAAAAA%3D

### SWC Info output

_No response_

### Expected behavior

The output should be this:
```js
console.log(1/ /* @__PURE__ */something())
```

### Actual behavior

The output is this:

```js
console.log(1//* @__PURE__ */something());
```

### Version

1.7.28

### Additional context

This just broke my builds very unexpectedly.
