Bug: `require-baseline` does not properly validate media conditions in `@media` rules
### Environment

ESLint version: v9.17.0
@eslint/css version: v0.3.0
Node version: v22.9.0
npm version: v10.9.1
Operating System: macOS


### Which language are you using?

stylesheet

### What did you do?

Tested `require-baseline` with media conditions.

<details>
<summary>Configuration</summary>

```js
import css from '@eslint/css';

export default [
  {
    files: ['**/*.css'],
    language: 'css/css',
    ...css.configs.recommended,
    rules: {
      'css/require-baseline': ['error', { available: 'widely' }],
    },
  },
];
```
</details>

```css
@media (color-gamut: srgb) {
  p {
    background: #f4ae8a;
  }
}
```


### What did you expect to happen?

An error:

```console
Media condition 'color-gamut' is not a widely available baseline feature.
```

### What actually happened?

No error was reported.

### Link to Minimal Reproducible Example

https://stackblitz.com/edit/vitejs-vite-w3knjrzj?file=src%2Findex.css

### Participation

- [x] I am willing to submit a pull request for this issue.

### Additional comments

_No response_
