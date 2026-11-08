Rule proposal: ensure style prop on DOM element tags is an object
React will issue a warning in dev if you pass a non-object to the `style` prop on DOM element tags

https://github.com/facebook/react/blob/85dcbf83/src/renderers/dom/shared/ReactDOMComponent.js#L204-L207

This should be easy enough to enforce for most cases with a linter rule.

Bad:

```jsx
<div style="foo" />
```

```jsx
<div style={true} />
```

```jsx
const styles = true;
<div style={styles} />
```

Good:

```jsx
<div style={{ color: 'red' }} />
```

```jsx
const styles = { color: 'red' };
<div style={styles} />
```

It would be even nicer if it validated that the values of the style object are all strings.

### Additional contract requirements

- The rule is named `style-prop-object` and is implemented at `lib/rules/style-prop-object.js`, exporting a standard ESLint rule object.
- When the `style` prop value is not an object, the rule reports the diagnostic message exactly: `Style prop value must be an object`.
