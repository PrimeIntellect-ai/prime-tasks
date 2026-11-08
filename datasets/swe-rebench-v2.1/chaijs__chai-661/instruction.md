stack trace wrong for overridden properties
let's say I use the following assertion:

```js
expect(true).to.be.undefined;
```

I get the following error with the expected stack trace:

```
AssertionError: expected true to be undefined
 at Context.<anonymous> (test/test.js:18:25)
```

---

If I overwrite the `undefined` property like this:

```js
Assertion.overwriteProperty('undefined', function(_super) {
  return function() {
    _super.call(this);
  };
});
```

I'm getting the following error with an extended stack trace:

```
AssertionError: expected true to be undefined
 at Assertion.<anonymous> (src/chai-files.js:52:12)
 at Assertion.Object.defineProperty.get (node_modules/chai/lib/chai/utils/overwriteProperty.js:50:37)
 at Context.<anonymous> (test/test.js:18:25)
```

---

If I overwrite the `undefined` property like this:

```js
Assertion.overwriteProperty('undefined', function(_super) {
  return function() {
    this.assert(false, 'foo', 'bar');
  };
});
```

I'm getting the following error with a missing stack trace:

```
AssertionError: foo
```
