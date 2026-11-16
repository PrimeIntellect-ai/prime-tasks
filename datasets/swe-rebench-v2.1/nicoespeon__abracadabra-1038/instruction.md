Inline variable overwrites unrelated parameter
## Describe the bug

Inlining a variable doesn't only replace the references, but also parameters that shadow it.
Seems to only happen for methods/functions/setters inside an object.

## How to reproduce

Move the cursor to the first foo and execute `Inline variable`.

```js
var foo = 1;
console.log(foo);
fn({
  set(foo) {
    return foo;
  },
});

```

## Expected behavior

Only inline references of the variable.

```js
console.log(1);
fn({
  set(foo) {
    return foo;
  },
});

```

## Current behavior

It also replaces the `foo` parameter.

```js
console.log(1);
fn({
  set(1) {
    return 1;
  },
});
```

## Additional information

- Version of the extension impacted: _v9.3.0_
- Related: #316
