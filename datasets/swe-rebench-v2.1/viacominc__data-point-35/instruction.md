PathReducer mapping
This would be a new feature, the idea is to use the same pattern for entity mapping which is to add `[]` at the end of an entity id:

`hash:Foo[]`

this feature would expect the same mapping behavior but using a ReducerPath:

`$some.path[]`

By adding a `[]` at the end of a ReducerPath the developer should expect to get a mapping of the path passed.

```js
const input = [
   { a: { b: { c: 'foo' }}},
   { a: { b: { c: 'bar' }}},
]
dataPoint.transform('$a.b.c[]', input)
  .then( acc => {
    // ['foo', 'bar']
    console.log(acc.value)
  })
```

### Additional contract requirements

- When a path ending in `[]` is applied to an array, resolve that path against each array element and return the results as an array. If the input value is not an array, return `null`.
