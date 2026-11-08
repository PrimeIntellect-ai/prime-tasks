Namespace generated inner classes
If you have two components with the same name with different parent classes, they generate conflicting classes.

```kotlin
class Foo1 {
  @Component abstract class MyComponent()
}
class Foo2 {
  @Component abstract class MyComponent()
}
```

both generates `InjectMyComponent()` which causes a compile error.
