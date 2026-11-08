Compiler with the plugin fails with an exception on anonymous object comparing
The code is:
```
assert(object {  }.toString() == "foo")
```
The exception:
~~~
The root cause java.lang.AssertionError was thrown at: org.jetbrains.kotlin.backend.jvm.lower.AnonymousObjectSuperConstructorLowering.visitBlock(AnonymousObjectSuperConstructorLowering.kt:70)
...
Caused by: java.lang.AssertionError: object literal does not end in a constructor call
	at org.jetbrains.kotlin.backend.jvm.lower.AnonymousObjectSuperConstructorLowering.visitBlock(AnonymousObjectSuperConstructorLowering.kt:70)
	at org.jetbrains.kotlin.ir.visitors.IrElementTransformerVoid.visitBlock(IrElementTransformerVoid.kt:170)
	at org.jetbrains.kotlin.ir.visitors.IrElementTransformerVoid.visitBlock(IrElementTransformerVoid.kt:24)
~~~

### Additional contract requirements

- For the source
```kotlin
fun main() {
  assert(object { override fun toString() = "ANONYMOUS" }.toString() == "toString()")
}
```
the plugin must produce this exact multi-line assertion failure message:
```
Assertion failed
assert(object { override fun toString() = "ANONYMOUS" }.toString() == "toString()")
       |                                                |          |
       |                                                |          false
       |                                                ANONYMOUS
       ANONYMOUS
```
