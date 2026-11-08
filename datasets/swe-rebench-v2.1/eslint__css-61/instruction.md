Bug: `:has()` not flagged with Baseline Widely available config
### Environment

ESLint version: 9.20.1
@eslint/css version: 0.4.0
Node version: 20.0.0
npm version: 9.6.4
Operating System: MacOS 14.7.3


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
/* baseline/has (low) */
p:has(i) {
  color: sandybrown;
}
```


### What did you expect to happen?

The `:has()` pseudo-class is not yet Baseline Widely available, according to [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/:has):

<img width="713" alt="Image" src="https://github.com/user-attachments/assets/1b4835a4-c4c1-43a4-a619-a98784e47121" />

I would have expected `npx eslint src/has.css` to emit a warning that it "is not a widely available baseline feature"

### What actually happened?

No warnings were emitted

### Link to Minimal Reproducible Example

https://github.com/rviscomi/baseline-demos/tree/main/eslint

### Participation

- [x] I am willing to submit a pull request for this issue.

### Additional comments

_No response_

### Additional contract requirements

- For this warning, use `messageId: "notBaselineSelector"` and data `{ selector: "has", availability: "widely" }`. Highlight the complete `:has` token, including its leading colon; for `h1:has(+ h2) { margin: 0 0 0.25rem 0; }`, the range is line 1, column 3 through line 1, column 7.
