Computing type of `new java.lang.Enum[Foo]()` throws `NonMethodReferenceException`
```scala
enum Foo extends java.lang.Enum[Foo]:
  case Bar
```

Somewhere inside the tree of `Foo` there is an `Apply` tree: `new java.lang.Enum[Foo]()`. If I compute the type of this tree it throws `NonMethodReferenceException` [HIDDEN]

### Additional contract requirements

- Computing the type of the `java.lang.Enum[Foo]` constructor application must succeed and yield the applied type `java.lang.Enum[Foo]`.
