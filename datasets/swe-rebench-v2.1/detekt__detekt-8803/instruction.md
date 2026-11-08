False positive RedundantSuspendModifier with interface default implementation
With 2.0.0-alpha.1, there's a false positive `RedundantSuspendModifier` warning here if `foo` has a default implementation that doesn't make any suspend calls, even though the implementation needs `suspend`.

This seems to be a regression compared to 1.23.8.

```kotlin
interface Interface {
    // RedundantSuspendModifier - [Function has redundant `suspend` modifier.]
    suspend fun foo(): Int = 0
}

class Impl : Interface {
    override suspend fun foo(): Int {
        delay(1000)
        return 1
    }
}
```
