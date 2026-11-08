Injected nullable function argument loses nullability
Expected:
```kotlin
@Inject class Foo(bar: Bar?)

@Component abstract class MyComponent { abstract val foo: (Bar?) -> Foo }
```
to compile but fails because it generates:
```kotlin
class InjectMyComponent { override val foo: Function0<Bar> get() = ... }
```
