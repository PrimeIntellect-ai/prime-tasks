Rule proposal: avoid before / after hooks
Using `before` or `after` hooks is almost always a sign that you use shared state between multiple tests. This could lead to unwanted side-effects, e.g. some tests only pass/fail if the tests are executed in a specific order.

### Additional contract requirements

Expose the rule under the public identifier `no-hooks`. In addition to `before` and `after`, report calls to `beforeEach` and `afterEach`. A member call such as `foo.before()` and a non-call reference to a hook-named identifier are not violations merely because their names match a hook.
