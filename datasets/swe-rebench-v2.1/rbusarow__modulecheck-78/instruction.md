Autocorrect doesn't work when declaring a dependency with a configuration name string
In the Kotlin DSL, all configurations have String extension functions for declaring dependencies, such as:

``` Kotlin
dependencies {
  "implementation"(project(":library"))
}
```

These functions are probably most common in Android apps which use custom build flavors, because AGP does not generate normal non-String functions for those configurations.

Autocorrect should match declarations using Strings just like it does the conventional functions.
