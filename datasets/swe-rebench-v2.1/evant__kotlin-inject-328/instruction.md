Providing a function instead of property seems to not always work
Hello there 👋
Thanks for the fantastic library - made it really easy to convert an android app using dagger to a multi-platform app using kotlin-inject. I couldn't wish for anything more.

## Background
We need to have our component expose a type `Foo` _that is also_ used inside the component by another type `Bar`. This did work when the provisioning was declared as a property on the component, but seems to not work when instead using a function. It looks like the generated code still tries to call the function as a property. At first I thought we are having caching issues here.

## Minimal example
I created a minimal example repo here: https://github.com/degill/kotlin-inject-fun-bug-example

But it boils down to these lines:

```kotlin
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appComponent = AppComponent::class.create()
        appComponent.provideBar()
    }
}

@Component
abstract class AppComponent {
    @Provides
    fun FooImpl.bind(): Foo = this
//    abstract fun provideFoo(): Foo // Will not compile with error "Function invocation 'provideFoo()' expected"
    abstract val provideFoo: Foo // Will compile fine
    abstract fun provideBar(): Bar
}

interface Foo
@Inject
class FooImpl : Foo

@Inject
class Bar(val foo: Foo)
```

## Actual behaviour:
The code that gets generated tries to call `provideFoo` as a property:
```kotlin
public class InjectAppComponent() : AppComponent() {
  override fun provideFoo(): Foo = FooImpl().bind()

  override fun provideBar(): Bar = Bar(
    foo = provideFoo // With error "Function invocation 'provideFoo()' expected"
  )
}
```

## Expected behaviour
In the `README.md` it says using either way should work:
> In your component you can declare abstract read-only properties or functions to return an instance of a given type.

But maybe I overlooked something.
