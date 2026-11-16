Nested AssistedModule compilation fails with missing include error
Given the following module:
```java
class Outer {
  @AssistedModule
  @Module(includes = AssistedInject_TestModule.class)
  public abstract class TestModule {}
}
```

Compilation fails with:
```
error: @AssistedModule's @Module must include AssistedInject_TestModule
```

I am not certain if nested module not being allowed is intentional or not but it seems it should either be allowed or have a specific error as output.

I have a failing unit test and will open a PR with that once I have this issue link.

### Additional contract requirements

Nested assisted modules must be supported: an `@AssistedModule`-annotated `@Module` class nested inside one or more enclosing classes must compile successfully rather than being rejected.

In the same package, the generated module class name must place all enclosing type names, from outermost to innermost and joined by underscores, between the `AssistedInject_` prefix and the module's simple name. For example, a `TestModule` nested in `Outer.Inner` generates `AssistedInject_Outer_Inner_TestModule`.
