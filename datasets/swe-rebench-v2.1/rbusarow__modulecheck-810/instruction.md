An overshot dependency used in multiple downstream source sets is only added to one of them
I'm using an Android project as an example because it has a compatible SourceSet hierarchy by default, but this isn't an Android-specific bug.

Assume Android project has the dependency `implementation(project(":lib1"))`.

It doesn't use `:lib1` in `main`, or `debug`/`release`, but it does use `:lib1` in both `androidTest` and `test`.

Currently, ModuleCheck will find that it's overshot and should be both `androidTestImplementation` and `testImplementation`, but will only report one of them.  Which one is reported is random.

[HIDDEN]

### Additional contract requirements

- The fix is not Android-specific. In a non-Android (JVM) project with a compatible source-set
  hierarchy, an overshot dependency used in multiple downstream source sets must likewise be added
  to each corresponding configuration. For example, an `api` dependency used in both the `debug`
  and `test` source sets of a JVM project must be added to both `debugApi` and `testImplementation`.
- A dependency path must not be reported or added more than once to the same target configuration, even when multiple recommendations lead to that pair.
