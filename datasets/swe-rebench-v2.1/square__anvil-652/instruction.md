FR: Generate MapKeyCreator classes in factory gen
When using `@MapKey(unwrapValue = false)`, dagger generates creator classes for annotations that are consumed in components to create annotation instances. It would be useful to generate these in the signature Dagger expects as well.

```kotlin
// Given this
@MapKey(unwrapValue = false)
annotation class MultiScopeActivityKey(
  val value: KClass<out Activity>,
  val scope: KClass<*>,
)

// Generate this
object MultiScopeActivityKeyCreator {
  @JvmStatic
  fun createMultiScopeActivityKey(
    value: Class<out Activity>,
    scope: Class<*>
  ): MultiScopeActivityKey {
    return MultiScopeActivityKey(value.kotlin, scope.kotlin)
  }
}
```

The nice thing with Kotlin 1.7 is we can instantiate annotations directly, which is simpler than Dagger's standard mechanism of using AutoAnnotation
