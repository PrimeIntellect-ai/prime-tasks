`.not.have.keys` incorrectly failing
Because of [this line](https://github.com/chaijs/chai/blob/a64eb623449f058143930bd3a9d943985afa13b6/lib/chai/core/assertions.js#L1464) (I presume), the following tests both fail:

```js
expect({a: 1, b: 2, c: 3}).to.have.keys('a', 'b');  // Correctly fails
expect({a: 1, b: 2, c: 3}).to.not.have.keys('a', 'b'); // Should pass but it fails too
```

The second test is incorrectly failing; it should pass right away on the basis that the target and given values don't have the same number of keys, which is a requirement when the `contains` flag isn't set.
