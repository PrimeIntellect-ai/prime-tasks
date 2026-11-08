Kotlin source dirs for Android modules aren't parsed
This refers to using `src/main/kotlin` instead of `src/main/java`.

This works just fine in `java-library` modules, whether the module in question is the dependent or the dependency.

For Android modules, the source dir needs to be added like this:

```groovy
android {
  sourceSets {
    androidTest.java.srcDirs += 'src/androidTest/kotlin'
    main.java.srcDirs += 'src/main/kotlin'
    debug.java.srcDirs += 'src/debug/kotlin'
    release.java.srcDirs += 'src/release/kotlin'
    test.java.srcDirs += 'src/test/kotlin'
  }
}
```

This isn't hooking into the `KotlinCompile` task or anything like that, so it is included in the configuration when ModuleCheck tasks run.

The `src/main/kotlin` files are invisible to the parser, so anything which is only used inside that directory will be reported as unused.  And if the Android module is a library, then anything which is _declared_ inside that directory won't be counted.
