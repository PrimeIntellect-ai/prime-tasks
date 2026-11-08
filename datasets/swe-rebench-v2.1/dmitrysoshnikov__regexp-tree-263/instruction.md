Broken optimization `/^[\p{Mc}\p{Me}\p{Mn}]$/` -> `/^[Mcen\p{}]$/`
```
invalid Unicode escape \p
```

Or

```js
SyntaxError: Invalid regular expression: /^[Mcen\p{}]$/: Invalid property name in character class
```

### Additional contract requirements

- When optimizing `/[\w\p{L}]/u`, preserve it exactly: the serialized result must be `/[\w\p{L}]/u`.
