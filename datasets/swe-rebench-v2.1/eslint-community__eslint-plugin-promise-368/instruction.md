Regex patterns for param-names rule
### Description

The suggestion is to provide regex pattern options for `param-names` rule and support underscored names by default which are conventional for unused parameters.

### Steps to Reproduce

The cases that I've met more than once is unused `resolve` and a deferred that needs to avoid shadowing when exposing `resolve` and `reject` to parent scope:

```js
/*eslint promise/param-names: "error" */
let timeoutPromise = new Promise((_resolve, reject) => setTimeout(reject));
```

```js
/*eslint promise/param-names: ["error", { resolvePattern: 'resolve', rejectPattern: 'reject' }] */
let defer = () => {
  let resolve, reject;
  let promise = new Promise((resolveFn, resolveFn) =>{
    resolve = resolveFn;
    reject = rejectFn;
  });
  return { promise, resolve, reject };
};
```

**Expected behavior:**

`resolve` and `reject` can be named differently for a reason and this should be taken into account by a linter without drawing attention to it.

**Actual behavior:**

Parameter names are strictly compared against `resolve` and `reject` strings, and the rule accepts no additional options to change this.
