\@ in CSS Selector
* macOS Mojave 10.14 (18A391)
* Node.js 11.13.0
* npm 6.7.0
* webpack 4.29.6
* css-loader 2.1.1

### Expected Behavior

```HTML
<div class="m_x_@"></div>
```

### Actual Behavior

```SCSS
.m_x_\@ {
  margin-left: auto !important;
  margin-right: auto !important;
}
```

```JSX
/*
 * @flow
 */

import * as React from 'react';

import design from './design.scss';

class Test extends React.Component<P: {

}> {
  render () {
    return <div className={design['m_x_@']} />;
  }
}

export default Test;
```

```HTML
<div class="m_x_----wB9u"></div>
```

### Code

```js
const path = require('path');

const MiniCssExtractPlugin = require('mini-css-extract-plugin');
const sass = require('sass');

const isProduction = process.env.NODE_ENV === 'production';

const js = {
  exclude: /node_modules/,
  test: /\.js$/,
  use: [
    {
      loader: 'babel-loader',
    },
  ],
};

module.exports = {
  devtool: isProduction ? '' : 'source-map',
  entry: {
    index: path.resolve(__dirname, 'private/index.js'),
  },
  mode: isProduction ? 'production' : 'development',
  module: {
    rules: [
      js,
      {
        exclude: /node_modules/,
        test: /\.scss$/,
        use: [
          MiniCssExtractPlugin.loader,
          {
            loader: 'css-loader',
            options: {
              importLoaders: 2,
              localIdentName: isProduction ? '[hash:base64:8]' : '[local]--[hash:base64:4]',
              modules: true,
              sourceMap: !isProduction,
            },
          },
          {
            loader: 'postcss-loader',
            options: {
              plugins: [
                require('autoprefixer'),
              ],
              sourceMap: !isProduction,
            },
          },
          {
            loader: 'sass-loader',
            options: {
              implementation: sass,
              outputStyle: isProduction ? 'compressed' : 'expanded',
              sourceMap: !isProduction,
            },
          },
        ],
      },
    ],
  },
  output: {
    filename: '[name].js',
    path: path.resolve(__dirname, 'public'),
  },
  plugins: [
    new MiniCssExtractPlugin(),
  ],
};
```
