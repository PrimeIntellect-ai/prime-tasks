Option `localIdentRegExp` doesn't work after upgraded to 6.0.
- Operating System: Arch Linux
- Node Version: 16.4.2
- NPM Version: 7.17.0
- webpack Version: 5.45.1
- css-loader Version: 6.0.0

### Expected Behavior

`[1]` placeholder should be replaced with the matched pattern.

### Actual Behavior

`[1]` appears in generated class names.

### Code

```js
{
  loader: require.resolve("css-loader"),
  options: {
    modules: {
      localIdentName: "[1]__[local]__[hash:base64:8]",
      localIdentRegExp: /[/\\]([^/\\]+?)(?:\.module)?\.[^./\\]+$/,
    },
  },
},
```

### How Do We Reproduce?

It seems that the `localIdentRegExp` option has never been used in the default `getLocalIdent` function. If that's the expected behavior, please note that in the changelog as a breaking change.
