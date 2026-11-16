Limit `prefer-await-to-then` to execution
### Description

Hi,

I'm doing some type-checking for thenables and would prefer not to have `prefer-await-to-then` reported for such cases as this.

Might some detection be added to only insist on `await` when `then` was being *executed*?

### Steps to Reproduce

1.

```js
const isThenable = (obj) => {
  return obj && typeof obj.then === 'function';
};
```

**Expected behavior:** [What you expect to happen]

`promise/prefer-await-to-then` would not be reported in this case and only for cases like:

```js
obj.then((resolve, reject) => {...});
```

**Actual behavior:** [What actually happens]

`promise/prefer-await-to-then` is reported.
