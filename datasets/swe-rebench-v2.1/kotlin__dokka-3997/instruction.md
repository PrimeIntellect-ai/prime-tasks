Supertypes for java source use incorrect generics
Sample java source:
```java
class Bar<T> {}
public class Foo extends Bar<String> {}
```

The super class type of `Foo` should be `Bar<String>`, but the `supertypes` on the `DClass` for `Foo` instead includes the type `Bar<T>`, using the type parameter from the definition of `Bar` instead of the concrete type used in `Foo`'s definition.

(This is handled correctly for kotlin source.)
