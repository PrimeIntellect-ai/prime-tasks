aws-sdk: warning on deployment


# This is a Bug Report

## Description

Updated webpack serverless and now get warning when deploying

```
Serverless: WARNING: Runtime dependency 'aws-sdk' found in devDependencies. You should use forceExclude to explicitly exclude it.
```

Config:
```
const slsw = require('serverless-webpack');
const nodeExternals = require('webpack-node-externals');
const Dotenv = require('dotenv-webpack');

module.exports = {
  entry: slsw.lib.entries,
  target: 'node',
  // Generate sourcemaps for proper error messages
  devtool: 'source-map',
  // Since 'aws-sdk' is not compatible with webpack,
  // we exclude all node dependencies
  externals: [nodeExternals()],
  mode: slsw.lib.webpack.isLocal
    ? 'development'
    : 'production',
  optimization: {
    // We no not want to minimize our code.
    minimize: false
  },
  performance: {
    // Turn off size warnings for entry points
    hints: false
  },
  plugins: [new Dotenv()],
  // Run babel on all .js files and skip those in node_modules
  module: {
    rules: [
      {
        test: /\.js$/,
        loader: 'babel-loader',
        include: __dirname,
        exclude: /node_modules/
      }
    ]
  }
};

```




Similar or dependent issue(s):


## Additional Data

* ***Serverless-Webpack Version you're using***: 5.1.5
* ***Webpack version you're using***: 4.8.3
* ***Serverless Framework Version you're using***: 1.27.2
* ***Operating System***: linux
* ***Stack Trace (if available)***:

### Additional contract requirements

- When `aws-sdk` is found in `devDependencies`, the informational log message must contain `INFO: Runtime dependency 'aws-sdk' found in devDependencies`.

- For `aws-sdk` found in `devDependencies`, do not emit the reported warning telling the user to use `forceExclude`.
