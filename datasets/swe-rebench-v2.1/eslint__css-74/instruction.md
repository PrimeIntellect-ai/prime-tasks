Bug: generate-baseline misses many functions
### Environment

Node version: v20.0.0
npm version: v9.6.4
Local ESLint version: v9.21.0 (Currently used)
Global ESLint version: Not found
@eslint/css version: 0.4.0
Operating System: darwin 23.6.0

### Which language are you using?

stylesheet

### What did you do?

<details>
<summary>Configuration</summary>

```
import globals from "globals";
import css from "@eslint/css";


/** @type {import('eslint').Linter.Config[]} */
export default [
  {
    languageOptions: {
      globals: globals.browser
    }
  },
  {
    files: ["**/*.css"],
    plugins: {
      css,
    },
    language: "css/css",
    rules: {
      "css/require-baseline": ["warn", {
        "available": "widely"
      }],
    },
  },
];
```
</details>

```css
/** src/functions.css */
a {
  background: color-mix(in srgb, lightblue, white 80%);
}

div {
  background: conic-gradient(from 0deg at 0% 25%, blue, green, yellow 180deg);
}
```

```sh
npx eslint src/functions.css
```

### What did you expect to happen?

ESLint should warn when Baseline newly available features like `color-mix` and `conic-gradient` are used.

I'd also expect the `types` map within [baseline-data.js](https://github.com/eslint/css/blob/9c7fd6aa06b62c70d979ff5f7b9c06a95fdeed56/src/data/baseline-data.js#L560) to include entries for functions like `color-mix` and `conic-gradient`.

There is a related [`color`](https://github.com/eslint/css/blob/9c7fd6aa06b62c70d979ff5f7b9c06a95fdeed56/src/data/baseline-data.js#L573) entry, but its Baseline status should be Newly available (5) according to [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color).

### What actually happened?

ESLint doesn't emit any warnings for these newly available features, despite the config being set to widely available.

`color-mix` and `conic-gradient` aren't listed in the `types` map, and `color` has a Baseline status of Widely available (10).

### Link to Minimal Reproducible Example

https://github.com/rviscomi/baseline-demos/blob/main/eslint/src/functions.css

### Participation

- [x] I am willing to submit a pull request for this issue.

### Additional comments

The `cssTypePattern` regex seems to be responsible for this:

https://github.com/eslint/css/blob/9c7fd6aa06b62c70d979ff5f7b9c06a95fdeed56/tools/generate-baseline.js#L77

### Additional contract requirements

- For `a { color: color-mix(in hsl, hsl(200 50 80), coral 80%); }`, report the warning on line 1 from column 12 through column 56, covering the `color-mix(...)` function call.
- The rule must warn for many newly available CSS functions, not only `color-mix`. For example, `conic-gradient`, `hsl`, `hwb`, `lab`, and `oklch` are newly available functions that must be reported.
