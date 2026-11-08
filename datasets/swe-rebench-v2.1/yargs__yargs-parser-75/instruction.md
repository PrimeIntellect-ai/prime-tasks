wrong behavior when flatten-duplicate-arrays and duplicate-arguments-array are enabled
@nexdrew pointed out this edge-case:

when you enable both  flatten-duplicate-arrays and duplicate-arguments-array are enabled

```json
{
  "yargs": {
    "flatten-duplicate-arrays": false,
    "duplicate-arguments-array": false
  }
}
```

Running:

```
node test.js -x 1 2 3 -x 2 3 4
```

results in:

```
{ _: [],
  x: [ [ '1', '2', '3' ], [ '2', '3', '4' ] ],
  '$0': 'test.js' }
```

It seems like it would be more consistent with this new API for the result to be `x: ['2', '3', '4']`

CC: @laggingreflex if you're looking for your next contribution to yargs, would love help adding a test and fix for this.
