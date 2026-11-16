EMPTY_BLOCK_STRUCTURE_ERROR shouldn't trigger on empty lambdas
## Describe the bug
Sometimes empty lambda can be used as a function that does nothing:
```kotlin
fun foo(bar: () -> Unit = {})
```
or empty function in implementation of functional interface:
```kotlin
A({})  // instead of A(Disposable {}), where Disposable is functional interface from Java
```
Diktat shouldn't issue a warning in these cases, because they are valid and can't be done differentlty. Also, kotlin copiler warns that `Unit` is redundant in `{ Unit }`.

## Environment information
* diktat version: 0.4.2
