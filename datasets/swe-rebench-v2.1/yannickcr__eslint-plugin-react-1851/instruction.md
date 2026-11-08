False positive for react/button-has-type
The following code triggers `react/button-has-type`.

```js
document.createElement('button')
```

The culprit is in this function: https://github.com/yannickcr/eslint-plugin-react/blob/master/lib/rules/button-has-type.js[HIDDEN]

This should also check for the `pragma` setting.

### Additional contract requirements

- `react/button-has-type` must not report `document.createElement('button')`.
- The rule must apply its missing-type check to button elements created through the configured pragma, such as `Foo.createElement('button')` when the pragma is `Foo`.
