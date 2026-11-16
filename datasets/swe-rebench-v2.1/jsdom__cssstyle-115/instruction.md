Doesn't support `calc`
```js
import cssstyle from "cssstyle";

export const stringifyCssText = (styleObject: object): string => {
  let cssText = "";
  const style = new cssstyle.CSSStyleDeclaration(newCssText => {
    cssText = newCssText;
  });
  Object.assign(style, styleObject);

  return cssText;
};
console.log(
  stringifyCssText({
    width: "100vh",
    height: "calc(100vh * 2)"
  })
);
// will output `width: 100vh;` but `height` is missing
```

Demo here https://codesandbox.io/s/flamboyant-moore-983md

### Additional contract requirements

- The `parsers` module must expose a `TYPES.CALC` value.
- `parsers.valueType("calc(100px * 2)")` must return `TYPES.CALC`.
