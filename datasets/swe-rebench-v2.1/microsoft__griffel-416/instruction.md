eslint-plugin: enforce ::before over :before
ESLint plugin should prevent usage of ":before":

```js
makeStyles({
  // ❌ should throw
  root: {
    ":before": {}
  },
  // ✅ should pass
  root: {
    "::before": {}
  }
});
```

- check our codebase for ":before"/":after"
- rule should implement autofix

### Additional contract requirements

- Apply the naming rule to `:after` as well as `:before`: accept `::after` and correct a single-colon `:after` by adding a colon.
- Treat `:before` or `:after` at the root of a `makeStyles` style object as a slot name, not as a pseudo-element selector. Diagnose and correct those names when they occur as selectors within a slot's style.
- Make the rule available through the ESLint plugin's exported rules so consumers can enable it.
- Audit existing repository styles for legacy single-colon pseudo-element selectors and correct any invalid usages found.
