Kotlin data class boolean properties with "is" prefix are ignored
When generating a schema for following Kotlin data class, no definition is created for the `isBool` attribute.
```kotlin
  data class TestIsBoolean(val isBool: Boolean)
```

I suspect that it has to do with some Kotlin-specific naming logic that removes the prefix in compile time.
It's still not clear to me why the attribute is ignored completely rather than defined without the prefix.
Of course, the expected behavior, in this case, would be to have a schema property called `isBool`.

I'll be happy to contribute a fix, but not sure where to start. Any idea what the root cause is and how to approach fixing it?

### Additional contract requirements

- The fix must also apply to plain Java types, not only to Kotlin data classes. When a class declares a boolean field named `isBool` together with a getter method named `isBool()`, that getter must be associated with that field (and that field with that getter), so that the generated schema contains a property named `isBool` instead of ignoring the field.
