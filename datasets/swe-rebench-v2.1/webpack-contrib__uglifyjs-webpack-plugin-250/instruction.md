Legal, License, Copyright comments should not be removed by default
**Steps to reproduce:**

Version in `package.json`:
```json
    "grunt-webpack": "^3.0.2",
    "uglifyjs-webpack-plugin": "^1.1.8",
    "webpack": "^3.10.0",
    "webpack-bundle-analyzer": "^2.9.2"
```

My `webpack.config.js`:
```js
const path = require('path');
const webpack = require('webpack');
const UglifyJSPlugin = require('uglifyjs-webpack-plugin');
const BundleAnalyzerPlugin = require('webpack-bundle-analyzer')
  .BundleAnalyzerPlugin;

const config = {
  // entry: ["babel-polyfill", "./app/js"]
  entry: {
    // Further entry points can be added here
    // NB: If you add further ones, then you probably also want to move
    // dependencies like jQuery into their own bundle
    // see https://webpack.js.org/guides/code-splitting/#prevent-duplication

    // the babel-polyfill and fetch polyfill needs to be loaded only once,
    // hence only added to app.js which is executed on every page
    app: ['babel-polyfill', 'whatwg-fetch', './src/components/app.js'],
    resizer: ['./src/prototype-assets/viewport-resizer/main.js'],
    fractalmenuenhancer: [
      './src/prototype-assets/fractal-menu-enhancer/main.js'
    ]
  },
  module: {
    rules: [
      {
        test: /\.js$/,
        exclude: /node_modules/,
        use: {
          loader: 'babel-loader'
        }
      }
    ]
  },
  resolve: {
    extensions: ['*', '.js', '.jsx']
  },
  output: {
    filename: '[name].bundle.js',
    path: path.resolve(__dirname, 'public/js/')
  },
  plugins: [
    new webpack.EnvironmentPlugin({
      // pass 'development' unless process.env.NODE_ENV is defined to further tasks/loaders/babel
      NODE_ENV: 'development'
    })
  ]
};

// Extend config to use best, small build for prod and fast, big for dev
if (process.env.NODE_ENV === 'production') {
  config.devtool = 'source-map';
  config.plugins.push(
    new UglifyJSPlugin({
      sourceMap: true
    })
  );
  config.plugins.push(
    new BundleAnalyzerPlugin({
      analyzerMode: 'static',
      reportFilename: '../webpack-bundle-size-analyser.html',
      openAnalyzer: false
    })
  );
} else {
  config.devtool = 'eval-source-map';
}

module.exports = config;
```

Now in the `./src/components/app.js` there are several 'vendor' libraries imported like: `import $ from 'jquery';`

**Actual results:**
When running `npm run build` which creates a uglified minimal bundle, then *all* comments are stripped.

For instance, `jquery` has this header which is not present any more in the uglified bundle:
```
/*!
 * jQuery JavaScript Library v3.3.1
 * https://jquery.com/
 *
 * Includes Sizzle.js
 * https://sizzlejs.com/
 *
 * Copyright JS Foundation and other contributors
 * Released under the MIT license
 * https://jquery.org/license
 *
 * Date: 2018-01-20T17:24Z
 */
```

**Expected results:**
Legal copyright comments should not be stripped by default. The comment at https://github.com/webpack/webpack/issues/324#issuecomment-157855568 points out, that

> it's intended that webpack preserves some comments. This is for legal reasons. By default comments with @license, @preserve or starting with /*! are preserved

At the moment this is not the case: By default *all* comments are stripped at the moment.
