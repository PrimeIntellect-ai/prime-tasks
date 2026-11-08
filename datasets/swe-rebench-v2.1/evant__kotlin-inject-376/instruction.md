Implemented function still considered abstract
Imagine this example:
```kotlin
interface Interface1 {
  fun string(): String
}

interface Interface2 : Interface1 {
  override fun string(): String = "abc"
}

@Component
abstract class MyComponent1 : Interface1, Interface2
```
This fails with:
```
Cannot find an @Inject constructor or provider for: String
```
But if I change the order of the super types to the following, then the code compiles successfully:
```kotlin
@Component
abstract class MyComponent1 : Interface2, Interface1
```
