`AVOID_NULL_CHECKS` conflicts with `NO_BRACES_IN_CONDITIONALS_AND_LOOPS`
## Describe the bug
```kotlin
fun foo() {
    if (a) {
        bar()
    } else if (b != null) {
        baz()
    } else {
        qux()
    }
}
```

## Observed behavior
Diktat changes `else` to `let` and then complains that there are no braces
```
...
Warn (4:7) [NO_BRACES_IN_CONDITIONALS_AND_LOOPS] in if, else, when, for, do, and while statements braces should be used. Exception: single line if statement.: ELSE
...
```
```kotlin
fun foo() {
    if (a) {
        bar()
    } else b?.let {
        baz()
    }
        ?: run {
            qux()
        }
}
```

## Environment information
* diktat version: 1.0.1

### Additional contract requirements

- Do not report `NO_BRACES_IN_CONDITIONALS_AND_LOOPS` for an `else` branch whose expression is a direct `let`, `run`, or `apply` scope-function call, including `b?.let { ... }`, `b!!.run { ... }`, and `b.apply { ... }`. This exemption also applies to an Elvis expression such as `b?.let { ... } ?: run { ... }`.
- A scope-function call nested inside another expression, such as `else baz(b.apply { ... })`, does not exempt the `else` branch from the braces rule.
