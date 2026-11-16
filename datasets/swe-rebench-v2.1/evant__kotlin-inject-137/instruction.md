Support receivers on inject functions
Currently the following generates incorrect code:

```kotlin
typealias foo = String.() -> String
@Inject
fun String.foo(bar: Bar): String = ...

@Component
abstract class MyComponent {
  abstract val foo: foo
}
```
