Find reducers can't return falsy values
**Problem description**:

```js
const reducer = find(x => x === 0)
const input = [0, 1, 2]
// this should return 0, but it returns undefined instead
dataPoint.resolve(reducer, input)
```

**Suggested solution**:

Refactor the `ReducerFilter#resolve` function.
