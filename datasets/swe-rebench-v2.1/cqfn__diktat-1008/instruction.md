LAMBDA_IS_NOT_LAST_PARAMETER: incorrectly treats argument with nullable functional type as not functional
## Describe the bug
```kotlin
fun foo(lambda1: () -> Unit,
             lambda2: (() -> Unit)?
) {}
```
emits warning `LAMBDA_IS_NOT_LAST_PARAMETER`, but if `lambda2` is non-nullable, there is no warning:
```kotlin
fun foo(lambda1: () -> Unit,
             lambda2: (() -> Unit)
) {}
```

## Environment information
* diktat version: 1.0.0-rc.2
