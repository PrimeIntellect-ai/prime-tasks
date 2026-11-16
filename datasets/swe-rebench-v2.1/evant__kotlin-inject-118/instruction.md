Support typealias for @IntoMap
Normally typealiases are treated as separate types, but here it should look through them to see the Pair as it's useful to re-use across provides.

```kotlin
typealias MyEntry = Pair<MyKey, MyValue>

@Component
abstract class MyComponent {
   @Provides @IntoMap
   fun entry1(): MyEntry = ...
   @Provides @IntoMap
   fun entry2(): MyEntry = ...
}
```

### Additional contract requirements

A component that contributes entries with `@Provides @IntoMap` where the provided value's declared type is a type alias for `Pair<K, V>` exposes the contributed entries as a `Map<K, V>` keyed by the entry key.
