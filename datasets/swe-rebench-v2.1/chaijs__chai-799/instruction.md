Consistency with returning new Assertion instead of this
A change was made a few months ago to return a new Assertion object with flags copied over instead of returning `this`. References: #562 #642

However, it looks like there are still some spots where `this` is returned. The only one I've actually tested so far is [overwriteProperty](https://github.com/chaijs/chai/blob/e5e6f5cbbd0e3542f928559f2d290663facd82e5/lib/chai/utils/overwriteProperty.js#L61).

For example:

```js
const {expect, use} = require("chai");

use(function (chai, utils) {
  utils.overwriteProperty(chai.Assertion.prototype, "and", function (_super) {
    return function blah () {
      _super.call(this);
    };
  });
});

it("but", () => {
  expect([1, 2, 3]).to.be.an.but.length.below(1000)    // Passes
});

it("and", () => {
  expect([1, 2, 3]).to.be.an.and.length.below(1000)    // Fails
});
```

As expected, the second assertion fails with error: "TypeError: expect(...).to.be.an.and.length.below is not a function" because the overwritten `and` is returning the function that was originally returned by the chainable method `an` instead of returning a new Assertion.

Other places where this might be a problem (but I haven't tested):

- [overwriteMethod](https://github.com/chaijs/chai/blob/e5e6f5cbbd0e3542f928559f2d290663facd82e5/lib/chai/utils/overwriteMethod.js#L60)
- [addChainableMethod](https://github.com/chaijs/chai/blob/e5e6f5cbbd0e3542f928559f2d290663facd82e5/lib/chai/utils/addChainableMethod.js#L85)
- [overwriteChainableMethod](https://github.com/chaijs/chai/blob/e5e6f5cbbd0e3542f928559f2d290663facd82e5/lib/chai/utils/overwriteChainableMethod.js#L46-L52)

### Additional contract requirements

- When an added or overwritten assertion property or method returns `undefined`, chaining must continue with a new `Assertion` instance whose flags are copied from the original assertion.
- When an added chainable method returns `undefined`, chaining must continue with a new `Assertion` instance whose flags are copied from the original assertion.
- For an overwritten chainable method, this requirement applies both to its method implementation and to its chaining-behavior callback: if either returns `undefined`, chaining must continue with a new `Assertion` instance whose flags are copied from the original assertion.
