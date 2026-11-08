babel-plugin-minify-dead-code-elimination is too eager on jquery.js
## Input

```js
function test(props) {
  var isBox = "width" in props;

  for (prop in props) {
    delete props[prop];
  }
  // This also triggers the bug:
  // delete props.width;

  if (isBox) {
    console.log("hello");
  }
}
```

## Output

```js
function test(props) {

  for (prop in props) {
    delete props[prop];
  }
  // This also triggers the bug:
  // delete props.width;

  if ("width" in props) {
    console.log("hello");
  }
}
```

## Problem

The minifier inlines the `isBox` variable, which moves the `"width" in props` expression. However, at that point the "width" property has been removed from `props`, effectively making `"width" in props` always be `false`, so that `console.log("hello")` never runs.

Here's how I tested: https://github.com/lydell/babel-plugin-minify-dead-code-elimination-bug/blob/master/minimal.js

## jQuery!

This bugs affects jQuery!

A minimal repo with test cases can be found here: https://github.com/lydell/babel-plugin-minify-dead-code-elimination-bug

What happens is that after I’ve run babel-plugin-minify-dead-code-elimination on jquery.js (node_modules/jquery/dist/jquery.js), the [`.slideToggle()`](http://api.jquery.com/slideToggle/) method no longer behaves correctly: It _does_ animate the height of elements, but fails to apply `overflow: hidden;` while animating, making text inside elements overflow.

### Info

Here’s exactly how I run babel-plugin-minify-dead-code-elimination: https://github.com/lydell/babel-plugin-minify-dead-code-elimination-bug/blob/master/minify.js

Here’s the diff between input and output of jquery.js, so you can see what babel-plugin-minify-dead-code-elimination has done: https://github.com/lydell/babel-plugin-minify-dead-code-elimination-bug/blob/master/jquery.diff

I've also manually reverted changes made by the minifier until only the breaking change was left. Here's the diff for that: https://github.com/lydell/babel-plugin-minify-dead-code-elimination-bug/blob/master/jquery-edit.diff

In the production app where I discovered this, I use [babel-minify-webpack-plugin](https://github.com/webpack-contrib/babel-minify-webpack-plugin) and `new MinifyPlugin({deadcode: false})` is a workaround.

### Expected behavior (before minify)

<details>
<summary>Click to show gif</summary>
<img src="https://user-images.githubusercontent.com/2142817/30591096-ce211d94-9d41-11e7-992a-efafd5519be8.gif">
</details>


### Actual behavior (after minify)

<details>
<summary>Click to show gif</summary>
<img src="https://user-images.githubusercontent.com/2142817/30591108-d6e2510a-9d41-11e7-8423-7d0eb3dfa258.gif">
</details>
