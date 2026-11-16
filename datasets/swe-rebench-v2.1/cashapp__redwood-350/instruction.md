Switch children properties back to using lambdas
Now that we're not using the declared schema for testing and are going to take another approach (#335), we should restore the schema to using lambda types to define children. For unscoped children this change has no value, but for scoped children we can change this:
```kotlin
@Children(1, MyScope::Class) children: () -> Unit,
```
into this:
```kotlin
@Children(1) children: MyScope.() -> Unit,
```
which is much more natural and reflective of how it works in generated output.

### Additional contract requirements

A `@Children` property declared as `Receiver.() -> Unit` declares `Receiver` as its scope without a scope argument on `@Children`. Schema processing and generated output must retain and use that scope. Ordinary `() -> Unit` children remain valid and unscoped.
