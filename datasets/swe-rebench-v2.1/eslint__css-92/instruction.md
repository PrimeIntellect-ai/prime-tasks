Bug: `use-layers` rule's `layerNamePattern` does not support period-separated layer names
### Environment

ESLint version: v9.22.0
@eslint/css version: v0.5.0
Node version: v22.9.0
npm version: 10.5.0
Operating System: macOS 14.7


### Which language are you using?

stylesheet

### What did you do?

Tested `css/use-layers` rule with `layerNamePattern` option.

<details>
<summary>Configuration</summary>

```js
import css from "@eslint/css";

const eslintConfig = [
  {
    files: ["**/*.css"],
    language: "css/css",
    ...css.configs.recommended,
    rules: {
      "css/use-layers": ["error", { layerNamePattern: "^(reset|theme|base)$" }]
    },
  },
];

export default eslintConfig;
```
</details>

```css
@layer reset, base, theme;

@import url("reset.css") layer(base.theme);
@layer base.theme {
  a { color: red; }
}
```

### What did you expect to happen?

[Period-separated layer names](https://drafts.csswg.org/css-cascade-5/#layer-names) should be treated separately. In this case, `base` and `theme` should be handled as individual layers, and since both match the pattern, no warning should appear.

### What actually happened?

An error message appears:

```console
Expected layer name 'theme.base' to match pattern '^(reset|theme|base)$'
```

### Link to Minimal Reproducible Example

https://stackblitz.com/edit/vitejs-vite-qjgplxrs?file=src%2Findex.css

### Participation

- [x] I am willing to submit a pull request for this issue.

### Additional comments

Reference to the spec: [CSS Cascade and Inheritance Level 5 - Layer Names](https://drafts.csswg.org/css-cascade-5/#layer-names)
> When multiple identifiers are concatenated with a period, this is a shorthand representing those layers nested in order.

### Additional contract requirements

- For each nonmatching component of a period-separated layer name in an `@layer` rule or `@import` layer(), emit a separate diagnostic with `messageId: "layerNameMismatch"`, `data.name` set to that component, and `data.pattern` set to the configured pattern. The diagnostic source range must cover only that component.
