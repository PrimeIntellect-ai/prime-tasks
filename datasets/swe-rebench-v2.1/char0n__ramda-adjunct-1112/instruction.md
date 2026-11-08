isSafeInteger
Determines whether the provided value is a number that is a safe integer.

Complete description of what safe integer is, can be found here on [MDN](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Number/isSafeInteger). The linked page also contains polyfill and preferred implementation of the `isSafeInteger` function. Modern javascript already contains function `Number.isSafeInteger`.

Expected behavior
```js
RA.isSafeInteger(3);                    // true
RA.isSafeInteger(Math.pow(2, 53));      // false
RA.isSafeInteger(Math.pow(2, 53) - 1);  // true
RA.isSafeInteger(NaN);                  // false
RA.isSafeInteger(Infinity);             // false
RA.isSafeInteger('3');                  // false
RA.isSafeInteger(3.1);                  // false
RA.isSafeInteger(3.0);                  // true
```

[This PR](https://github.com/char0n/ramda-adjunct/pull/1067) should serve as a model template of PR for `isSafeInteger` function.

### Additional contract requirements

- The module `src/internal/polyfills/Number.isSafeInteger.js` provides a function `isSafeIntegerPolyfill(val)` that returns a boolean indicating whether `val` is a safe integer.
