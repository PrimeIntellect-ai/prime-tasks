[Bug] Data race in RoleManagerImpl.HasLink() breaks Enforcer when calling Enforce()
## **Describe the bug**

Setup:
* Initialized Casbin Enforcer or Synced Casbin Enforcer
* `AddNamedMatchingFunc()` used (e.g. keyMatch2, keyMatch4)

The bug is reproduced when calling `Enforce()` with the same parameters concurrently.

It boils down to this path being executed concurrently:
[HIDDEN]

Race explanation inside `HasLink()` function with goroutines A and B:
* Enforce A: Enter `HasLink()`. [HIDDEN]
* Enforce A: [HIDDEN]
* Enforce B: [HIDDEN]
* Enforce A: Exit function, [HIDDEN]
* Enforce B: [HIDDEN]
* Enforce A: `allow: true`
* Enforce B: `allow: false`

Furthermore once this happens, the calculation is cached in `GenerateGFunction` and also in [getAndStoreMatcherExpression()](https://github.com/casbin/casbin/blob/master/enforcer.go#L655), all further `Enforce()` calls for that set of parameters will incorrectly return a cached `false` response.

## **To Reproduce**

This behaviour does not occur all the time, but by disabling cache inside `GenerateGFunction` it is possible to reproduce it reliably:
1. Clone https://github.com/Metrika-Inc/casbin-race/
3. Run the test: `make test`
    * rerun if not reproduced on first time
4. Observe the panic due to Enforce() returning false [in the test](https://github.com/Metrika-Inc/casbin-race/blob/master/race_test.go#L69)

Check README in the [Metrika-Inc/casbin-race](https://github.com/Metrika-Inc/casbin-race) repository for more details.

## **Expected behavior**

Enforcer always returns true when correct policies are in place.

## Actual behavior
Enforcer sometimes returns false even when correct policies are in place and it may cache the result to continue returning false incorrectly.

## Environment
 - OS: macOS and Linux

## Possible solutions
[HIDDEN]

### Additional contract requirements

- With a stable role graph and a registered matching function, concurrent `HasLink()` calls must return the correct link result consistently.
- When configured policies authorize the inputs, concurrent `Enforce()` calls with the same inputs must return true.
- A transient incorrect denial during concurrent enforcement must not cause subsequent calls with the same authorized inputs to continue returning false because of a cached result.
