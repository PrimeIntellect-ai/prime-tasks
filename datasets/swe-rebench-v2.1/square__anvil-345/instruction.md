AssistedInject-annotated classes's factories don't account for member injection
Given this example

```kotlin
class Example @AssistedInject constructor() {
  @Inject lateinit var injected: String
}
```

The generated factory is missing a member injection call

```kotlin
public class Example_Factory(
  // private val param0: Provider<String> // <-- Missing parameter input
) : Factory<Example> {
  public override fun get(): Example {
    val instance = newInstance()
    [HIDDEN]
    return instance
  }
}
```

The relevant `MembersInjector` is correctly generated, just not accounted for here.
