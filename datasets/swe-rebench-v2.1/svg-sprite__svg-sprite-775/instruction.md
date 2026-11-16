Bug: Spriter's Shape Transform Method Only Running First Transformation in shape.transform Array
Repo with minimum reproduction: https://github.com/babs20/svg-sprite-transform-bug

**Steps to Reproduce:**
1. Use the Spriter configuration below
2. Add SVG files to spriter instance
3. Run the compile method on the spriter
4. You will see that the output log only shows the optimization, but not the `console.log` in the second transformation. Also, if you inspect the output SVG you will see the custom transformations were not applied.

**Expected Behavior:**
SVGO optimizes shape, then my custom transformation runs on the shape.

**Actual Behavior:**
Whichever transformation comes first in the `shape.transform` array is run on the shape, but the subsequent transformations are not run.

**Sidenotes**
- This works with `svg-sprite@1.5.4`, but is broken in `svg-sprite@^2`
- I did a little digging into the source code and found that both transformations were being added to the `async.waterfall` correctly in `Spriter._transformShape` but, the second transformation function was not being called for some reason.
- I tried `node@12`, `node@14`, `node@16`, and `node@18`
- I am using Windows 11

Here is an example of my spriter config.
```js
const spriter = new SVGSpriter({
  dest: "",
  shape: {
    dimension: {
      maxWidth: 100,
      maxHeight: 100,
      precision: 2,
      attributes: false,
    },
    dest: "",
    transform: [
      "svgo",
      {
        custom: (shape, sprite, callback) => {
          console.log("2nd Transformation");
          const svgEl = shape.dom.getElementsByTagName("svg");
          const paths = shape.dom.getElementsByTagName("path");

          for (let i = 0; i < svgEl.length; i++) {
            svgEl[i].removeAttribute("fill");
          }

          for (let i = 0; i < paths.length; i++) {
            paths[i].setAttribute("fill", "");
          }

          callback(null);
        },
      },
    ],
  },
  expand: true,
  cwd: "sourceimages/sourceimages/svg",
  src: ["**/*.svg"],
  mode: {
    symbol: {
      bust: false,
      prefix: ".icon-%s",
      render: {
        scss: false,
        css: false,
      },
      example: true,
    },
  },
  log: "debug",
});
