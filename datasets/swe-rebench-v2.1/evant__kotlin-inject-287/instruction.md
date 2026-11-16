Multi-bindings does not work with type aliases
Suppose I have a component such as:
```kotlin
@Component
abstract class MyComponent {
  @Provides @IntoSet fun integer(): Int = 1
  @Provides @IntoSet fun myNumber(): MyNumber = 2

  abstract val integerSet: Set<Int>
  abstract val myNumberSet: Set<MyNumber>
}
```

Executing the following
```kotlin
with(MyComponent::class.create()) {
  println("Contents of integer set: $integerSet")
  println("Contents of myNumber set: $myNumberSet")
}
```

prints
```
Contents of integer set: [1]
Contents of myNumber set: [1]
```

Ideally `typealias` would allow generating another multibindings on the graph.

Use case: Having different set of Interceptors for OkHttp (regular and Network types).
