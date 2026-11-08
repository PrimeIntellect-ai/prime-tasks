react/jsx-key doesn't detect Array.from
[`react/jsx-key`](https://github.com/jsx-eslint/eslint-plugin-react/blob/master/docs/rules/jsx-key.md) doesn't detect a specific case where an iterable is [mapped using `Array.from`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/from#parameters):

```
const mySet = new Set()

// ...

// Should warn for missing key property, but doesn't
Array.from(mySet, () => <div />)
```
