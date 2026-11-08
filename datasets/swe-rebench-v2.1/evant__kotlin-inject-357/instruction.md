Scope annotations aren't picked up when scanning superclasses
In the following case `FooSingleton` isn't picked up from the `BaseFooComponent` interface:

```kotlin
@Scope
annotation class FooSingleton

interface Foo

@Inject
class MyFoo : Foo

@Inject
class FooHolder(
  private val foo: Foo
)

interface BaseFooComponent {
  @Provides @FooSingleton fun provideFoo(): Foo
}

@FooSingleton
@Component
abstract class FooComponent : BaseFooComponent {
  override fun provideFoo(): Foo = MyFoo()

  abstract val holder: FooHolder

  companion object
}
```

The following is generated, without `provideFoo` being scoped:

```kotlin
public fun FooComponent.Companion.create(): FooComponent = InjectFooComponent()

public class InjectFooComponent() : FooComponent(), ScopedComponent {
  override val _scoped: LazyMap = LazyMap()

  override val holder: FooHolder
    get() = FooHolder(
      foo = provideFoo()
    )
}
```

Adding `@FooSingleton` to `provideFoo` in `FooComponent` does cause it to get scoped:

```kotlin
public fun FooComponent.Companion.create(): FooComponent = InjectFooComponent()

public class InjectFooComponent() : FooComponent(), ScopedComponent {
  override val _scoped: LazyMap = LazyMap()

  override val holder: FooHolder
    get() = FooHolder(
      foo = _scoped.get("com.example.Foo") {
        provideFoo()
      }
    )
}
```
