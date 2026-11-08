Escaped query string value doesn't propagate to downstream loader
- Operating System: macOS 11.2
- Node Version: 12.18.3
- NPM Version: 6.14.6
- webpack Version: 4.27.0
- css-loader Version: 5.0.1

### Code

**webpack.config.js**

```js
const path = require('path');

module.exports = {
  context: __dirname,
  entry: './example.css',
  output: {
    path: path.resolve(__dirname),
    filename: 'bundle.js',
  },
  module: {
    rules: [
      {
        test: /\.svg$/i,
        resourceQuery: /color/,
        enforce: 'pre',
        use: {
          loader: path.resolve(__dirname, './svg-color-loader.js'),
        },
      },
      {
        test: /\.svg$/i,
        use: {
          loader: 'file-loader',
        },
      },
      {
        test: /\.css$/i,
        use: {
          loader: 'css-loader',
        },
      },
    ],
  },
};
```

**example.css**

```css
.example {
  background-image: url('./example.svg?color=%23BAAFDB');
}
```

**svg-color-loader.js**

```js
const { parseQuery } = require('loader-utils');

module.exports = function(source) {
  const query = parseQuery(this.resourceQuery);

  // transform `source` based on the value of `query.color`
};
```

### Expected Behavior

The `query` object in `svg-color-loader.js` is `{ color: '#BAAFDB' }`. (This used to be the case in `css-loader` v3.)

### Actual Behavior

The `query` object in `svg-color-loader.js` is `{ color: '' }`.

### Notes

I'm not sure if this is the same issue as #1048.

I am attempting to upgrade `css-loader` from v3 to v5. However it now seems to treat the escaped query string value `%23BAAFDB` differently. Is this a bug in `css-loader` (i.e. it's mistakenly parsing  `%23BAAFDB` as a URL fragment?) or is there some alternative approach I should use for my downstream loader?

Thanks.
