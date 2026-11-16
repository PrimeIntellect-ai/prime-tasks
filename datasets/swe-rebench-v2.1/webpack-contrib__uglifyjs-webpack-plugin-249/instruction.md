`extractComments` option uses url relative to `output.path` instead of its source file
<!-- Please don't delete this template or we'll close your issue -->
<!-- Before creating an issue please make sure you are using the latest version of webpack. -->
<!-- Also consider trying the webpack@beta version, maybe it's already fixed. -->

**Do you want to request a *feature* or report a *bug*?**
I'm not sure, it's probably a FR

<!-- Please ask questions on StackOverflow or the webpack Gitter (https://gitter.im/webpack/webpack). -->
<!-- Issues which contain questions or support requests will be closed. -->

**What is the current behavior?**
When using the `UglifyjsWebpackPlugin` with the following options...

```js
const uglifyConfig = {
    sourceMap: true,
    extractComments: /(?:^!|@(?:license|preserve))/i
}
```

...the file is written in the correct folder but the path that is written into the file is relative to the base directory (I guess it's the `output.path` option) instead of the file. As an example I'm getting:

```
/*! For license information please see chunks/polyfill-url-search-params/index.123hash.js.LICENSE */
```

In production, this path is wrong because the relative directory to the `LICENSE` file, so it would be located in: `http://example.com/chunks/polyfill-url-search-params/chunks/polyfill-url-search-params/index.123hash.js.LICENSE`

**If the current behavior is a bug, please provide the steps to reproduce.**

<!-- A great way to do this is to provide your configuration via a GitHub gist. -->
<!-- Best provide a minimal reproduceable repo -->
<!-- If your issue is caused by a plugin or loader file the issue on the plugin/loader repo -->

**What is the expected behavior?**
I was expecting the path to be relative to the file it was extracted out of, in the same way the sourcemap comment is relative to it's base file. So I'd expect this comment:

```
/*! For license information please see index.9aa3a7a3fab51a749ce0.js.LICENSE */
```

One option would be to provide the source file path so I could do a manual path rewrite with a function for the `filename` option.

**If this is a feature request, what is motivation or use case for changing the behavior?**
As all the files are hosted in the same directory (`file.123hash.js`, `file.123hash.js.map`, `file.123hash.js.LICENCE`) it's necessary that the url that is found within the file is also relative to the path it is found in.

**Please mention other relevant information such as the browser version, Node.js version, webpack version and Operating System.**
Version: webpack 3.8.1

Wepback config:
```
const config = {
    entry: {
        app: '/Repository-Root/some-cwd/src/app/main/index.js',
        vendor: ['vendor-libs'],
    },
    output: {
        path: '/Repository-Root/some-cwd/dist',
        filename: `entry/[name]/index.js`,
        chunkFilename: `chunks/[name]/index.[chunkhash].js`,
        devtoolModuleFilenameTemplate: 'source-webpack:///[resourcePath]',
        devtoolFallbackModuleFilenameTemplate: 'source-webpack:///[resourcePath]?[hash]'
    },
    plugins: [
        new webpack.optimize.CommonsChunkPlugin({ name: 'vendor', minChunks: Infinity }),
        new webpack.optimize.CommonsChunkPlugin({ name: 'runtime' }),
        new webpack.optimize.UglifyJsPlugin(uglifyConfig)
    ],
    resolve: {
        modules: [
            'node_modules',
            '/Repository-Root/some-cwd/src/app'
        ],
    },
}
```

---

This issue was moved from webpack/webpack#6059 by @evilebottnawi. Orginal issue was by @Nirazul.
