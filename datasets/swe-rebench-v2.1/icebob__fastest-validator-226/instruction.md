tuple item dosent support default and optioanl
default
```ts
const V = require('fastest-validator');

const v = new V();

const schema = {
  tuple: {
    type: 'tuple',
    empty: false,
    items: [{ type: 'string', default: '1' }],
  },
};

const data = { tuple: [] };
console.log(v.validate(data, schema));
console.log(data);
```

```text
[
  {
    type: 'tupleEmpty',
    message: "The 'tuple' field must not be an empty array.",
    field: 'tuple',
    actual: []
  }
]
{ tuple: [] }
```

optional
```ts
const schema = {
  tuple: {
    type: 'tuple',
    empty: false,
    items: [
      { type: 'string' },
      { type: 'number', optional: true },
    ],
  },
};

const data = { tuple: ['str', undefined] };
console.log(v.validate(data, schema));
console.log(data);
```

```text
[
  {
    type: 'number',
    message: "The 'tuple[1]' field must be a number.",
    field: 'tuple[1]',
    actual: undefined
  }
]
{ tuple: [ 'str', undefined ] }
```

### Additional contract requirements

- Array and tuple item schemas accept a `default` property and an `optional` boolean property.
- When an item's value is `undefined`, the item's declared `default` value is written into that position of the array or tuple.
- An item marked `optional: true` accepts an `undefined` value without producing a validation error.
- Defaults and optional flags apply to the item positions that exist in the array or tuple; a tuple must still contain exactly as many items as its `items` list.
