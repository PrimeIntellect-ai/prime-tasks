max-top-level-suites not being triggered for mocha/recommended plugin
It's mentioned in the rules [markdown](https://github.com/lo1tuma/eslint-plugin-mocha/tree/master/docs/rules#rules) that `max-top-level-suites` is included in the `mocha/recommended` plugin.

However, I'm _not_ able to trigger the rule with the following simple test:
```javascript
import * as assert from 'assert';

describe('Array.length', function () {
  it('should return the correct length of the array', function () {
    assert.equal([1, 2, 3].length, 3);
  });
});

describe('Array.indexOf()', function () {
  it('should return -1 when the value is not present', function () {
    assert.equal([1, 2, 3].indexOf(4), -1);
  });
});
```

What seems weird to me is that I _am_ able to trigger the other rules (e.g. `no-global-tests`, `no-identical-title`).
