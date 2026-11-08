Incorrect wrapping into `apply` function
## Describe the bug
```kotlin
fun fo() {
    val pair = it.split("=", limit = 2).map {
        it.replace("\\=", "=")
    }
    pair.first() to pair.last()
}
```

## Expected behavior:
Rule shouldn't trigger, because top-level node is an infix function, not dot-qualified call, from which we can extract receiver.
Also, it can potentially break in other cases, when result of dot-qualified call is implicitly returned. If we wrap it into `apply`, we will break the code, while wrapping into `run` will not.

## Observed behavior
```kotlin
fun fo() {
    val pair = it.split("=", limit = 2).map {
        it.replace("\\=", "=")
    }.apply {
        first() to pair.last()
    }
}
```

## Environment information
* diktat version: 1.0.0-rc.3
