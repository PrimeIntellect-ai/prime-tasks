Add analysis of fully-qualified expression in NewLines rule
## Describe the bug

Fully-qualified expression should not be separated

## Initial code:

```kotlin
private val holder: java.util.concurrent.atomic.AtomicReference<T> = java.util.concurrent.atomic.AtomicReference(valueToStore)
```



```kotlin
private val holder: kotlin.native.concurrent.AtomicReference<T> = kotlin.native.concurrent.AtomicReference(valueToStore)
```

## Expected behavior

```kotlin
private val holder: java.util.concurrent.atomic.AtomicReference<T> = java.util.concurrent.atomic.AtomicReference(valueToStore)
```



```kotlin
private val holder: kotlin.native.concurrent.AtomicReference<T> = kotlin.native.concurrent.AtomicReference(valueToStore)
```

## Observed behavior

```kotlin
private val holder: java.util.concurrent.atomic.AtomicReference<T> = java.util
        .concurrent
        .atomic
        .AtomicReference(valueToStore)
```



```kotlin
private val holder: kotlin.native.concurrent.AtomicReference<T> = kotlin.native
        .concurrent
        .AtomicReference(valueToStore)
```

## Environment information
* diktat version: 1.2.0
* kotlin version: 1.6

### Additional contract requirements

When the rule reports a violation for a long `dot qualified expression` or `safe access expression`, the emitted warning message must be exactly:

    [WRONG_NEWLINES] incorrect line breaking: wrong split long `dot qualified expression` or `safe access expression`
