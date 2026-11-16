bug: Decorator is not applied properly
**Describe the bug**
Decorator is not applied properly when it is not required through a "direct" dependency.

**To Reproduce**
See https://github.com/uber-go/fx/pull/939.

**Expected behavior**
The test added in https://github.com/uber-go/fx/pull/939

Internal Ref: GO-1668

### Additional contract requirements

- A decorator must be applied when its value is consumed indirectly by a provider that contributes a value to a group, and the application requests that group. The consuming provider must observe the decorated value; decoration must not be limited to values requested as direct dependencies.
