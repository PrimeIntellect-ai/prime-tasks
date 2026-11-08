[NoNameShadowing] False negative inside lambdas
## Expected Behavior
```kotlin
fun asdf(rotation: Float, onClick: (Float) -> Unit) {
    foo {
        asdf(rotation) { rotation -> onClick(rotation) }
    }
}

fun foo(block: () -> Unit) {
}
```

on that code I expect to have a violation of this rule because `rotation ->` shadows `rotation: Float` from the main function.

But if the code is like this:

```kotlin
fun asdf(rotation: Float, onClick: (Float) -> Unit) {
    asdf(rotation) { rotation -> onClick(rotation) }
}
```

The rule catches the problem.

## Observed Behavior
Nothing is marked as shadowed.

## Context
I know that this rule only relies on the kotlin compiler warnings but they seem a bit too lax.

Also, this type of pattern happens a lot on Compose because nearly always you are inside a `Box` or a `Column` and that "disables" this rule.

This issue is related to this other: https://github.com/appKODE/detekt-rules-compose/issues/41 but for sure they are two different issues.

## Your Environment
* Version of detekt used: 1.23.7
