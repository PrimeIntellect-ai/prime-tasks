v.1.1.1 throw error when accessing the page
<!--
  Issues are so 🔥

  If you remove or skip this template, you'll make the 🐼 sad and the mighty god
  of Github will appear and pile-drive the close button from a great height
  while making animal noises.

  👉🏽 Need support, advice, or help? Don't open an issue!
  Head to StackOverflow or https://gitter.im/webpack/webpack.
-->

- Operating System: macOS 10.14.6
- Node Version: 12.14.0
- NPM Version: 6.13.4 (yarn 1.19.1)
- webpack Version: 4.41.3
- style-loader Version: 1.1.1

### Expected Behavior
`style-loader` operating normally
<!-- Remove this section if not reporting a bug or modification request. -->

### Actual Behavior

After I upgraded from 1.0.2 to 1.1.1, webpack compiles, but I get an error (`Uncaught RangeError: Invalid array length`) when accessing the webpage.When I downgrade 1.0.2, it's fine.

<!-- Remove this section if not reporting a bug or modification request. -->

### Code

```js
// webpack.config.js
// If your code blocks are over 20 lines, please paste a link to a gist
// (https://gist.github.com).
{
        test: /\.s?css$/,
        use: [
          "style-loader",
          MiniCssExtractPlugin.loader,
          "css-loader",
          "postcss-loader",
          "sass-loader"
        ]
}
```

### How Do We Reproduce?

Stated in "Actual Behavior".

<!--
  Remove this section if not reporting a bug.

  If your webpack config is over 50 lines long, please provide a URL to a repo
  for your beefy 🍖 app that we can use to reproduce.
-->
