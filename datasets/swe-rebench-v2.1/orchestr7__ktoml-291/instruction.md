error decoding map: key is not a valid map index
I tried this:

```kotlin
val d = mapOf("key" to "value")
val t = Toml.encodeToString(d)

Toml.decodeFromString<Map<String,String>>(t)
```
It throws an `IllegalArgumentException: key is not a valid map index`.

This seems so simple that maybe I'm using it wrong?


It works fine with `Json` serialization.
