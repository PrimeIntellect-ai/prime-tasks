Remove java.lang.String import from generated components
This snippet
 ```
import me.tatarka.inject.annotations.Component
import me.tatarka.inject.annotations.Inject
import me.tatarka.inject.annotations.Provides

fun main() {
    TestComponent::class.create("Hello World").factory.print()
}

@Component
abstract class TestComponent(@get:Provides protected val string: String) {
    abstract val factory: HelloWorldFactory
}

@Inject class HelloWorldFactory(private val string: String) {

    fun print() = println(string)
}
```
Generates this:
```
import java.lang.String
import kotlin.reflect.KClass

class InjectTestComponent(
  string: String
) : TestComponent(string) {
  override val factory: HelloWorldFactory
    get() = HelloWorldFactory(string)}

fun KClass<TestComponent>.create(string: String): TestComponent = InjectTestComponent(string)
```

Which yields this error:
```
Type mismatch.
Required:java.lang.String
Found:kotlin.String
```
![image](https://user-images.githubusercontent.com/1403243/90938325-d5eff200-e3d6-11ea-8942-40cd61c6898a.png)
