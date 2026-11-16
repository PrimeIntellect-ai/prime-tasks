Couldn't parse bundle asset "vendors~typeahead.chunk.min.js". Analyzer will use module sizes from stats file.
Plugin version 1.2.4
webpack 4

This only happens in production when setting ` sourceMap: false`, when set to true, it runs fine!

```
 new UglifyJsPlugin({
            sourceMap: false, // <-- using false here, generates the error above
            uglifyOptions: {
                ecma: 5,
                warnings: true
            }
        })
```

**Here the complete Log-file:**
[2018-03-16T16_31_25_817Z-debug.log](https://github.com/webpack-contrib/uglifyjs-webpack-plugin/files/1820016/2018-03-16T16_31_25_817Z-debug.log)

### Additional contract requirements

- Add a public function `isSourceMap(input)` in module `src/utils/index.js`. It returns `true` when `input` is an object with truthy `version`, `sources`, `names`, and `mappings` properties, and `false` otherwise.
- When a bundle asset provides a source map that is not a valid source map, the plugin records a warning on the compilation instead of processing that map, and the compilation does not fail.


- Export `isSourceMap` as a property of the default export from `src/utils/index.js`.
- For an invalid source map on asset `test4.js`, the warning message must be exactly `test4.js contain invalid source map`.
