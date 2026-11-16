`Provider<Lazy<...>>` is not handled correctly
Given this example:

```kotlin
class Example @Inject constructor(
  private val injected: Provider<Lazy<String>>
)
```

Anvil generates this

```kotlin
public class Example_Factory(
  private val param0: Provider<@JvmSuppressWildcards Lazy<String>>
) : Factory<Example> {
```

This isn't correct though, as dagger components will try to just pass it `Provider<String>` and expect the factory to handle lazy-ing it.

```java
public final class Example_Factory implements Factory<Example> {
  private final Provider<String> stringProvider;

  public Example_Factory(
      Provider<String> stringProvider) {
    this.stringProvider = stringProvider;
  }

  @Override
  public Example get() {
    [HIDDEN]
  }

  public static Example_Factory create(
      Provider<String> stringProvider) {
    return new Example_Factory(stringProvider);
  }

  public static Example newInstance(
      Provider<Lazy<String>> stringProvider) {
    return new Example(stringProvider);
  }
}
```

### Additional contract requirements

- For a constructor parameter of type `Provider<Lazy<T>>`, the generated factory constructor and `create` method must accept a `Provider<T>`.
- Calling the generated factory’s `get()` must create an instance whose constructor receives a `Provider<Lazy<T>>` corresponding to that `Provider<T>`.
- The generated `newInstance` method must accept a `Provider<Lazy<T>>` and pass it to the injected class constructor.
