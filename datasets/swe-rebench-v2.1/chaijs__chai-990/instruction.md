Error or not updated docs on assert.isAbove and isBelow
Hi.

`assert.isAbove` and `assert.isBelow` used to take Dates as possible inputs and worked fine, but since v4.0.0 it errors with `expected *date* to be a number` resulting in numerous failed test-cases throughout my codebase after an update from 3.5.

So my guess is either the documentation was not updated (as it currently lists {Mixed} type for an input) or it's a bug - either way there seems to be a problem. Just wanted to ask which one is it.

It's reproducible both in Mocha (Node) and in the browser (dev console on the official website with `4.0.0-canary.2` at the moment of this issue)

Is there is indeed a problem or have I misunderstood something?
And how can I help?

### Additional contract requirements

The comparison assertions accept either numbers or `Date` objects:

- `above(n)` and `assert.isAbove(actual, n)` assert the target is strictly greater than `n`.
- `least(n)` and `assert.isAtLeast(actual, n)` assert the target is greater than or equal to `n`.
- `below(n)` and `assert.isBelow(actual, n)` assert the target is strictly less than `n`.
- `most(n)` and `assert.isAtMost(actual, n)` assert the target is less than or equal to `n`.
- `within(start, finish)` asserts the target is inclusively between `start` and `finish`.

When the target is a `Date`, the argument must also be a `Date`; when the target is a number, the argument must also be a number. `within` requires both bounds to be the same type (both numbers or both `Date`s). All of these also support length assertions (used after `.length` or `.lengthOf`), where the argument must be a number.

The assert-style functions `assert.isAbove`, `assert.isAtLeast`, `assert.isBelow` and `assert.isAtMost` return `undefined`. The fluent assertions return the assertion object so calls can be chained.

Error messages:

- If the target is neither a number nor a `Date` (and no length assertion is in effect), the assertion fails with `expected <value> to be a number or a date`.
- If the target is a `Date` and the argument is not a `Date`, the assertion fails with `the argument to <method> must be a date`, where `<method>` is `above`, `least`, `below` or `most`.
- If the target is a number (or a length assertion is in effect) and the argument is not a number, the assertion fails with `the argument to <method> must be a number`.
- `within` fails with `the arguments to within must be numbers` when the bounds are not both numbers, and `the arguments to within must be dates` when the bounds are not both `Date`s.
- When a comparison fails, the message is `expected <target> to be <relation> <argument>`, where `<relation>` is `above`, `at most`, `at least`, `below`, `within <start>..<finish>` or `not be within <start>..<finish>`. `Date` values are rendered using their UTC string representation.
- A supplied message is prefixed to the error message as `<message>: `.
