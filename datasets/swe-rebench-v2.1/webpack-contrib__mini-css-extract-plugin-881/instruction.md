TypeError: publicPath.replace is not a function when output.publicPath of webpack config is a function
<!-- Please don't delete this template otherwise your issue will be closed immediately -->
<!-- Before creating an issue please make sure you are using the latest version of webpack. -->

### Bug report

<!-- Please ask questions on discussions, StackOverflow or the webpack Gitter. -->
<!-- https://github.com/webpack/webpack/discussions -->
<!-- https://stackoverflow.com/questions/ask?tags=webpack -->
<!-- https://gitter.im/webpack/webpack -->
<!-- Issues which contain questions or support requests will be closed. -->

When using function in `output.publicPath` of Webpack config, the loader of mini-css-extract-plugin seems to handle this situation incorrectly and leading to an error(see below).

> If this is a bug, I'm glad to make a PR

### Actual Behavior

```plain
assets by status 822 bytes [cached] 1 asset
runtime modules 663 bytes 3 modules
cacheable modules 71 bytes
  ./src/index.js 32 bytes [built] [code generated]
  ./src/index.css 39 bytes [built] [code generated] [1 error]

ERROR in ./src/index.css
Module build failed (from ./node_modules/.pnpm/mini-css-extract-plugin@2.4.5_webpack@5.64.4/node_modules/mini-css-extract-plugin/dist/loader.js):
TypeError: publicPath.replace is not a function
    at Object.pitch (/Users/username/Workspace/test/webpack-demo/node_modules/.pnpm/mini-css-extract-plugin@2.4.5_webpack@5.64.4/node_modules/mini-css-extract-plugin/dist/loader.js:176:114)
 @ ./src/index.js 1:0-21

webpack 5.64.4 compiled with 1 error in 285 ms
```

### Expected Behavior

Expect no errors would be throw.

<!-- "It should work" is not a helpful explanation -->
<!-- Explain exactly how it should behave -->

### How Do We Reproduce?

Reproduce repository: https://github.com/roland-reed/mini-css-extract-plugin-function-public-path, steps are listed in README.md

I dig a little and find that the following code should be related:

https://github.com/webpack-contrib/mini-css-extract-plugin/blob/e8c08a1c252f18b03612903d5ec75ebcddc538e0/src/loader.js#L182-L192

<!-- A great way to do this is to provide your configuration via a GitHub repository -->
<!-- The most helpful is a minimal reproduction with instructions on how to reproduce -->
<!-- Repositories with too many files or large `webpack.config.js` files are not suitable -->
<!-- Please only add small code snippets directly into this issue -->
<!-- https://gist.github.com is a good place for longer code snippets -->
<!-- If your issue is caused by a plugin or loader, please create an issue on the loader/plugin repository instead -->

### Please paste the results of `npx webpack-cli info` here, and mention other relevant information

```plain
 npx webpack-cli info

  System:
    OS: macOS 12.0.1
    CPU: (12) x64 Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz
    Memory: 40.96 MB / 32.00 GB
  Binaries:
    Node: 14.15.4 - ~/.nvm/versions/node/v14.15.4/bin/node
    Yarn: 1.22.11 - ~/.nvm/versions/node/v14.15.4/bin/yarn
    npm: 6.14.10 - ~/.nvm/versions/node/v14.15.4/bin/npm
  Browsers:
    Chrome: 96.0.4664.55
    Firefox: 94.0.1
    Safari: 15.1
  Packages:
    css-loader: 6.5.1 => 6.5.1
    webpack: 5.64.4 => 5.64.4
    webpack-cli: 4.9.1 => 4.9.1
```
