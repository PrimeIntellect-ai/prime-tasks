ThrowsCount rule does not report violations in override functions
## Expected Behavior

Should report a violation of `ThrowsCount` (assuming a threshold of max 2 `throw` statements):

```kotlin
            override fun f3(x: Int) {
                when (x) {
                    1 -> throw IOException()
                    2 -> throw IOException()
                    3 -> throw IOException()
                }
            }
```
The use of the `override` keyword should not alter the outcome.

## Observed Behavior

Does not report a violation of `ThrowsCount`:

```kotlin
            override fun f3(x: Int) {
                when (x) {
                    1 -> throw IOException()
                    2 -> throw IOException()
                    3 -> throw IOException()
                }
            }
```

Does report a violation of `ThrowsCount`:

```kotlin
            fun f3(x: Int) {
                when (x) {
                    1 -> throw IOException()
                    2 -> throw IOException()
                    3 -> throw IOException()
                }
            }
```

## Steps to Reproduce

The above examples are taken from `ThrowsCountSpec.kt`.

## Context

When splitting code from ordinary classes into interfaces and implementing classes, detekt no longer provides value even though the function body is exactly the same.

In [this discussion](https://github.com/detekt/detekt/discussions/6723) we established that the rule should be changed to include override functions as well.

## Your Environment
* Version of detekt used: 1.23.4 and older
