Assisted injected args are incorrectly used in other dependencies
Given this:

```kotlin
@Component
abstract class MyComponent {
  abstract val test: (String) -> Test
  @Provides fun provideSomeString() = "string"
}

@Inject
class Test(
  @Assisted assistedString: String,
  private val unrelatedDependency: UnrelatedDependency,
)

@Inject
class UnrelatedDependency(someString: String)
```

The generated code looks like this:

```kotlin
public class InjectMyComponent() : MyComponent() {
  public override val test: Function1<String, Test>
    get() = { arg0 ->
      Test(
        assistedString = arg0,
        unrelatedDependency = UnrelatedDependency(
          someString = arg0 // This shouldn't be the assisted argument!
        )
      )
    }
}
```

This seems to have been introduced on `0.6.0`, but it also happens on `0.6.1-SNAPSHOT`.
