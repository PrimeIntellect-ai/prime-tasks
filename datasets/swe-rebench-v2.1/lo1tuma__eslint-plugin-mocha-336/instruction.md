Support function calls as custom names (to stop false warnings)
### Motivation

Hi. I'd like the following sorts of things to be supported, but they actually give errors in the recommended set:

```javascript
// Say we have a custom function (this one is supposed to ignore tests completely in some situations):
describe.on = (platform) => (process.env.PLATFORM === platform ? describe : (() => {}));

describe('does something', () => {
  before(...);

  // This isn't treated as a suite, so we can get errors about multiple top-level suites, multiple sibling hooks, etc:
  describe.on('windows')('nested', () => {
    before(...); // <- this is treated as a sibling of the above before.
  });
});
```
and
```javascript
const forEach = require('mocha-each');

forEach([ 1, 2, 3 ]).describe('works', (n) => {
  before(...); // <- this is treated as a hook at the top level, even though it's nested here.
  it(...);
});
```

### Possible solution

[HIDDEN] It's already the case that dotted names will work and can be specified as custom additional ones.
It's then possible for `additionalCustomNames` to support names of the form
* `{ name: 'describe.on()', type: 'suite' }`,
* `{ name: 'forEach().describe', type: 'suite' }`

so that I can selectively rule these ones *in* to the set of suites.

### Alternatives

* I tried turning off the rule with some `eslint-disable`s but we actually have too many (of the first form I gave in Motivation) to want to do this. And of course, we do want the rules in most places, so globally switching it off isn't suitable.
* In the related PR, my first attempt was to have call expressions with *just* the name, but this didn't work for the `max-top-level-suites` rule (because `describe.on()` and `describe.on()(...)` had the "same" name)

### Additional contract requirements

Names configured through `additionalCustomNames` may contain function-call components. They must be recognized according to their configured type: custom suites establish suite scope, and custom test cases are recognized as test cases. A function-call component and a further invocation of that expression are distinct name components, so chained calls can be configured and matched without collapsing them into one name.
