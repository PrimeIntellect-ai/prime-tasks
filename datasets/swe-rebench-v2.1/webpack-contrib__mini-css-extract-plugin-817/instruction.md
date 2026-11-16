outputOptions.pathInfo = true breaks sourcemaps
- Operating System:
- Node Version:
- NPM Version:
- webpack Version: 5.51.1
- mini-css-extract-plugin Version: 2.2.0

### Expected Behavior

Source map line numbers are correct, even with `outputOptions.pathinfo` is true

### Actual Behavior

https://github.com/webpack-contrib/mini-css-extract-plugin/pull/783 adds a 3 line comment block to the top of the output; so source map line numbers are all off by 3

### Code

### How Do We Reproduce?

With a sourcemapped setup, click on a css class link in browser dev tools, and notice that the link shows the wrong line in the source.

### Additional contract requirements

- When source maps are enabled and `outputOptions.pathinfo` is true, browser developer tools must map CSS rules to their correct original source lines, including when multiple CSS sources are combined.
