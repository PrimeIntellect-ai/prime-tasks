mini-html-webpack-plugin not being ignored by styleguidist
Documentation says:

> CommonsChunkPlugins, HtmlWebpackPlugin, UglifyJsPlugin, HotModuleReplacementPlugin plugins will be ignored because Styleguidist already includes them or they may break Styleguidist.

Unfortunately since react-styleguidist migrated to https://github.com/styleguidist/mini-html-webpack-plugin recently, it isn't being ignored which causes weird errors like this one:

![2018-04-16 at 15 11](https://user-images.githubusercontent.com/11071/38810943-7ed36cec-4188-11e8-9c6e-17288fa632e6.png)

### Additional contract requirements

- When merging webpack plugin configurations, ignore plugin instances whose constructor name is `MiniHtmlWebpackPlugin`.
