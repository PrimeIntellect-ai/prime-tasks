sourceMap always prepend a undefined
I found that `sourceRoot` does not necessarily exist, sometimes it equals `undefined`.

I look for some codes, and found that [`extract-loader`](https://github.com/peerigon/extract-loader/blob/master/src/extractLoader.js#L141), it uses `extractExports` function to transform, (`Function toString()`) `sandbox.module.exports`.

[HIDDEN]

I suggest `css-loader` can compatibles it, when the `sourceRoot` is undefined, or keeps the `sourceRoot` option.

- cssWithMappingToString: https://github.com/webpack-contrib/css-loader/blob/master/src/runtime/api.js#L61
- css-loader: https://github.com/webpack-contrib/css-loader/blob/master/src/index.js#L76

### Environment

- Operating System: osx 10.14.6
- Node Version: 12.6.0
- NPM Version: 6.11.3
- webpack Version: 4.41.4
- css-loader Version: 3.4.0

### Expected Behavior

Would not prepend `undefined`

### Actual Behavior

```css
body{color:red}body a{color:#fff}body.open{background-color:#fef}
/*# sourceURL=undefined/src/index.scss */
...
```

### Code
```json
// package.json
{
    "extract-loader": "3.1.0",
    "css-loader": "3.4.0",
    "sass-loader": "8.0.0",
    "node-sass": "4.13.0",
}
```

```javascript
// webpack config
{
  loader: 'extract-loader'
},
{
  loader: 'css-loader',
  options: {
    sourceMap: true
  }
},
{
  loader: 'sass-loader',
  options: {
    sourceMap: true,
    sassOptions: {
      sourceMapRoot: '/'
    }
  }
}
```

### Additional contract requirements

- When a source map has no `sourceRoot`, generated CSS must not prepend the literal `undefined` to its source URL.
