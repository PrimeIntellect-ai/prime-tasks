New rule: no-settled-after-test-helper
This rule should lint against using the `settled()` test helper directly after test helpers that already call `settled()` internally. Having to use this pattern is usually a sign of a deeper root cause issue that should be fixed.

**Bad**

```js
await click('.foo');
await settled();
```

```js
await fillIn('.foo');
await settled();
```

**Good**

```js
await waitFor('.foo');
await settled();
```

/cc @rwjblue
