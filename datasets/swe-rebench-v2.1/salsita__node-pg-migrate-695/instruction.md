regression pgm.sql no longer works with arrays
This used to work on the v3 branch, currently, it always quotes the variable which obviously breaks this.
And using `pgm.func` results in an `undefined`;

```js
exports.up = (pgm) => {
    pgm.sql('INSERT INTO states (id) VALUES {values};', {
        values: ['queued', 'busy', 'completed', 'failed'].map(e => `('${e}')`).join(', \n')
    });
};
```

Suggestion: make `pgm.sql` aware of `PgLiteral`, its not the most sugar-coated but it is fairly simple and allows for special cases, which is exactly what this is.

### Additional contract requirements

When a `PgLiteral` is supplied as a `pgm.sql` placeholder value, its SQL contents must be inserted verbatim, without ordinary string quoting or escaping.
