camelcased options using dot notation are turned to array when aliased
This is a follow-up of yargs/yargs#1620.

Reproduction code:
```js
const parse = require('yargs-parser')
console.dir(parse('--filter-module.a 1 --filter-module.b 2', {
  alias: {
    'filter-module': ['f'],
  }
}))
```

Output:
```bash
$ node index.js
{
  _: [],
  'filter-module': { a: 1, b: 2 },
  filterModule: { a: [ 1, 1 ], b: [ 2, 2 ] },
  f: { a: 1, b: 2 }
}
```

Expected output:
```bash
$ node index.js
{
  _: [],
  'filter-module': { a: 1, b: 2 },
  filterModule: { a: 1, b: 2 },
  f: { a: 1, b: 2 }
}
```

This works fine when the `f` alias is removed.

EDIT: this works fine too when not using dot notation.
