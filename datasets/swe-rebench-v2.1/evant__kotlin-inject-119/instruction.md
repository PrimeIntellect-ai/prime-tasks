Support injecting companion object
This generates incorrect code

```kotlin
interface IFoo {
  @Inject
  companion object : IFoo
}

@Component
abstract class MyComponent {
   abstract val foo: IFoo
   val IFoo.Companion.bind: IFoo @Provides get() = this
}
```

expected:

```kotlin
class InjectMyComponent : MyComponent {
  override val foo: IFoo get() = IFoo.bind
}
```

actual:

```kotlin
class InjectMyComponent : MyComponent {
  override val foo: IFoo get() = IFoo.Companion().bind
}
```
