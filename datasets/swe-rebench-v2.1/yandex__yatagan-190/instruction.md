[KSP2] Component getter not generated if it's present in two interfaces with the same method signature
```kotlin
  @Test
  fun reproduce() {
      givenKotlinSource("test.TestCase", """
          import com.yandex.yatagan.*
          import javax.inject.*

          class TestClass @Inject constructor()

          interface Deps1 {
              val testClass: TestClass
          }

          interface Deps2 {
              val testClass: TestClass
          }

          @Component
          interface RootComponent: Deps1, Deps2
      """.trimIndent())

      compileRunAndValidate()
  }
```
