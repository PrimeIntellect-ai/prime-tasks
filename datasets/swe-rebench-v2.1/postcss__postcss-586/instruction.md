Problem with source map detection in previous-map.es6
Hi i add autoprefixer-loader to my webpack config and get `Unsupported previous source map format` error. I traced problem to line: https://github.com/postcss/postcss/blob/master/lib/previous-map.es6#L70 and looks like it tests `mappings` when in [HIDDEN], so looks like we need to test [HIDDEN], [HIDDEN]
Or can some1 who knows source map internal kitchen suggest some better decision?

### Additional contract requirements

- A previous source map supplied as an object from another source-map package, including one whose mapping data uses that package’s internal representation, must be accepted rather than causing an `Unsupported previous source map format` error.
