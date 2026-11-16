8.6.1 : 'TypeError: loader.charAt is not a function' in webpack 2.2.1
I use webpack2.2.1 in vue1.0.28 , when i use extract-text-webpack-plugin in webpack configuration like this
```js
  ...
  var ExtractTextPlugin = require('extract-text-webpack-plugin')

  module: {
    rules: [
      {
        test: /\.vue$/,
        loader: 'vue-loader',
        options: {
          loaders: {
            stylus: ExtractTextPlugin.extract({
              use: [
                'css-loader?{discardComments:{removeAll:true}}',
                'stylus-loader'
              ],
              fallback: 'vue-style-loader'
            })
          },
          postcss: [
            require('autoprefixer')({
              browsers: ['> 0.1% in CN']
            })
          ]
        }
      }
    ]
  },
  ...
  plugins: [
    ...
    new ExtractTextPlugin({
      filename: '[name].[contenthash:8].css',
      disable: false,
      allChunks: true
    })
    ...
  ]
  ...

```
and it show me  this message:
**"Module build failed: TypeError: loader.charAt is not a function"**
when i remove the  extract-text-webpack-plugin like this
```js
  module: {
    rules: [
      {
        test: /\.vue$/,
        loader: 'vue-loader',
        options: {
          loaders: {
            stylus: 'vue-style-loader!css-loader!stylus-loader'
          },
          postcss: [
            require('autoprefixer')({
              browsers: ['> 0.1% in CN']
            })
          ]
        }
      }
    ]
  }
```
then it works.
by the way, webpack2.2.1 must use the new version of extract-text-webpack-plugin, so the latest version is
 "extract-text-webpack-plugin": "^2.0.0-rc.3",
so, i do not know it is my wrong in somewhere or it is a bug.
please help, thanks a lot!

---
update at 19:37 in china
I switched the version of "extract-text-webpack-plugin" to "^2.0.0-beta.5" and change my configuration in this code
```js
      {
        test: /\.vue$/,
        loader: 'vue-loader',
        options: {
          loaders: {
            stylus: ExtractTextPlugin.extract({
              loader: 'css-loader?{discardComments:{removeAll:true}}!stylus-loader',
              fallback: 'vue-style-loader'
            })
          },
          postcss: [
            require('autoprefixer')({
              browsers: ['> 0.1% in CN']
            })
          ]
        }
      }
```
finally, "extract-text-webpack-plugin" works

### Additional contract requirements

- vue-loader's `loaders` option accepts, for each language, either a single loader string or an array of loader definitions. A loader definition is an object with a `loader` string. The definitions are combined into a single loader chain and applied in order.
- The `extract-text-webpack-plugin` package exposes `ExtractTextPlugin.loader(options)`, which returns a loader definition usable as the `loader` value of an element in such an array, and `new ExtractTextPlugin(filename)`, which creates a plugin that writes the extracted CSS to `filename`.


- After collapsing each run of whitespace in the extracted CSS to a single space and trimming leading and trailing whitespace, the result must contain `h1 { color: #f00; }` and `h2 { color: green; }`.
