Bracket selectors are considered mixin parameters.
* Node Version: v6.10.3
* NPM Version: v5.5.1
* postcss-less Version: v1.1.3

### LESS

```less
.a,
.b[type=text] {
  color: blue;
}
```

### JavaScript

```js
let postCssLess = require('./dist/less-syntax');
const less = `
.a,
.b[type=text] {
  color: blue;
}
`;
const root = postCssLess.parse(less);
console.log(root);
```

### Expected Behavior
No `params` set to match other postcss outputs.

### Actual Behavior
Bracket selector is considered a `params` value.

### How can we reproduce the behavior?
Use above JS file at project root.
This issue was found when using `stylelint`.
