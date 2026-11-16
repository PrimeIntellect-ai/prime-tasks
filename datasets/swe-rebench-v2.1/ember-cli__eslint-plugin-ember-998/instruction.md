Auto-fixing 'no-get' with 'useOptionalChaining' broken with arrays
## Repro steps:
With
```
rules: {
  'ember/no-get': ['error', { useOptionalChaining: true }],
};
```
try to `--fix` the following code:
```
myFunc(myParam) {
  get(myParam, '0.myProperty');
}
```

## Expected results:
Probably something like
```
myParam['0']?.myProperty;
```

## Actual results:
```
myParam.0?.myProperty;
```
which crashes because `0` is not a valid identifier name

### Additional contract requirements

- For `this.get('0.foo')` with `useOptionalChaining: true`, the auto-fix must produce exactly `this[0]?.foo`.
- For `get(myParam, '0.myProperty')` with `useOptionalChaining: true`, the auto-fix must produce exactly `myParam[0]?.myProperty`.
