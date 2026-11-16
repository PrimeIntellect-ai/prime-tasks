`CLASS_SHOULD_NOT_BE_ABSTRACT` breaks code when abstract class implements an interface
## Describe the bug
```kotlin
interface I {
    fun foo()
}

abstract class A : I  // diktat raises CLASS_SHOULD_NOT_BE_ABSTRACT, changes `abstract` to `open` and breaks compilation

class B : A() {
    override fun foo() {}
}
```

## Observed behavior
Diktat raises CLASS_SHOULD_NOT_BE_ABSTRACT, changes `abstract` to `open` and breaks compilation

## Environment information
* diktat version: 1.0.1
