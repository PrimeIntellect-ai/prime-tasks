Parse number for importLoaders in query parameter
<!--
  Issues are so 🔥

  If you remove or skip this template, you'll make the 🐼 sad and the mighty god
  of Github will appear and pile-drive the close button from a great height
  while making animal noises.

  👉🏽 Need support, advice, or help? Don't open an issue!
  Head to StackOverflow or https://gitter.im/webpack/webpack.
-->

Following your instructions given in [this issue](https://github.com/webpack/loader-utils/issues/173)...

- Operating System: Debian Buster
- Node Version: 14.7.0
- NPM Version: 6.14.7
- webpack Version: 4.44.1
- css-loader Version: 4.2.1

### Expected Behavior / Situation

Run `webpack` with the following configuration, ie. containing an inline - string - definition of `css-loader` that contains number as value for `importLoaders`:

```js
module.exports = {
    // ...
    module: { rules: [{
        test: /\.css$/,
        use: ['style-loader', 'css-loader?importLoaders=1', 'postcss-loader'],
    }] },
    // ...
```

### Actual Behavior / Situation

Error thrown:

```
ValidationError: Invalid options object. CSS Loader has been initialized using an options object that does not match the API schema.
 - options.importLoaders should be one of these:
   boolean | integer
   -> Enables/Disables or setups number of loaders applied before CSS loader (https://github.com/webpack-contrib/css-loader#importloaders).
   Details:
    * options.importLoaders should be a boolean.
    * options.importLoaders should be a integer.
```

### Modification Proposal

[HIDDEN]

```diff
 // ...
         {
           "type": "integer"
[HIDDEN]
[HIDDEN]
         }
       ]
     },
 // ...
```

[HIDDEN]

```diff
     : loaderContext.sourceMap,
[HIDDEN]
[HIDDEN]
     esModule:
       typeof rawOptions.esModule === 'undefined' ? true : rawOptions.esModule,
   };
```

### Additional contract requirements

- A numeric string supplied for `importLoaders` in a loader query, such as `css-loader?importLoaders=1`, must be accepted and interpreted as its numeric value. It controls how many preceding loaders are applied to imported CSS.
