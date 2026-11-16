asArray reducer helper
**Problem description**:

When defining reducers, arrays become `ReducerLists`, but that might not always be the desired behavior.

In this code, the value of `transform:example` is equal to the resolved value of `request:2`:

```js
{
  'transform:example': [
    'request:1',
    'request:2'
  ]
}
```

However, if you want the result to be an array where `array[0]` is the result of `request:1` and `array[1]` is the result of `request:2`, the code gets clunky:

```js
{
  'transform:example': [
    {
      a: 'request:1',
      b: 'request:2'
    },
    [
      '$a',
      '$b'
    ]
  ]
}
```


**Suggested solution**:

Create an `asArray` reducer helper. This helper would take an array of reducers, resolve each of them, and return an array of the resolved values.

```js
const { asArray } = require('data-point').helpers

{
  // the result will be an array of length 2
  'transform:example': asArray([
    'request:1',
    'request:2'
  ])
}

### Additional contract requirements

The helper requested above is exposed publicly as `DataPoint.helpers.parallel` (the original issue named it `asArray`; the public name of the implemented helper is `parallel`). `DataPoint.helpers.parallel(reducers)` takes an array of reducer specifications and returns a reducer specification of type `ReducerParallel` that the DataPoint resolution engine uses. Resolving it produces an array containing each child reducer's resolved value, in the same order as the input array; an empty input array resolves to an empty array.
