Array of camel-cased option with ConfigObjects
```js
var args = parse('--watchFiles path1 --watchFiles path2', {
    array: ['watch-files'],
    configObjects: [{'watchFiles': 'path3'}],
    configuration: {
        'combine-arrays': true,
        'camel-case-expansion': true
    }
})
console.log(args);
// { _: [], watchFiles: [ 'path1', 'path2' ], 'watch-files': [ 'path1', 'path2' ] }
```

The result is incorrect, it should be:
```
{ _: [],
  watchFiles: [ 'path1', 'path2', 'path3' ],
  'watch-files': [ 'path1', 'path2', 'path3' ] }
```
The input of `--watchFiles` is not recognised as the camel-cased version of `--watch-files`.

yargs-parser: v13.0.0 and also current master.

### Additional contract requirements

- When `array: ['apple']` and `alias: { apple: 'a' }` are configured, parsing `-a red` with `configObjects: [{ a: 'sweet' }]` and `'combine-arrays': true` must produce `argv.apple` equal to `['red', 'sweet']`.
