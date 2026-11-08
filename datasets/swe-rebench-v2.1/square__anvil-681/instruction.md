boundType does not support Any
Same as https://github.com/square/anvil/issues/619

This piece of code:

```kotlin
@ContributesMultibinding(ActivityInjection::class, boundType = Any::class)
class TestViewModel @Inject constructor() : SimpleStackViewModel() {
...
}
```

Will throw the follow error:
```
com.squareup.anvil.compiler.api.AnvilCompilationException: Back-end (JVM) Internal error: com.squareup.anvil.annotations.ContributesMultibinding contributes a binding for kotlin.Any, but doesn't extend this type.
```

The `ContributesBindingGenerator` works correctly and the test introduced in https://github.com/square/anvil/pull/623/files passes, if there's a component the `BindingModuleGenerator` will fail when merging the classes.


The following test fails:
```kotlin
  @Test fun `the contributed multibinding class can extend Any explicitly`() {
    compile(
      """
      package com.squareup.test

      import com.squareup.anvil.annotations.MergeComponent
      import com.squareup.anvil.annotations.ContributesMultibinding

      @ContributesMultibinding(Int::class, boundType = Any::class)
      interface ContributingInterface

      @MergeComponent(
        scope = Int::class,
      )
      interface ApplicationComponent
      """,
      ) {
      assertThat(this.exitCode).isEqualTo(ExitCode.OK)
    }
  }

```

### Additional contract requirements

- A type annotated with `@ContributesMultibinding` and `boundType = Any::class` must compile successfully when a component merges it. This holds whether the annotated type is a class or an interface, and even when it does not explicitly declare a supertype other than `Any`.
- A type annotated with `@ContributesBinding` and `boundType = Any::class` must continue to compile successfully when a component is present and merges bindings.
