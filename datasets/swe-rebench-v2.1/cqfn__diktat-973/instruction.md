Bug in [COMPACT_OBJECT_INITIALIZATION]
## Describe the bug

In function extension, if you use `this` keyword, and `COMPACT_OBJECT_INITIALIZATION` applied, it's hides
the `this` from top level.

Consider the following code:

```kotlin
fun String.createPluginConfig() {
      val pluginConfig = TomlDecoder.decode<T>(
          serializer(),
          fakeFileNode,
          DecoderConf()
      )
      pluginConfig.configLocation = this.toPath()
}
```
## Expected behavior
It's shouldn't  be created `apply` block, if `this` exist, or should use annotations:

```kotlin
fun String.createPluginConfig() {
    val pluginConfig = TomlDecoder.decode<T>(
        serializer(),
        fakeFileNode,
        DecoderConf()
    ).apply {
        configLocation = this@createPluginConfig.toPath()
    }
}
```
## Observed behavior
```kotlin
fun String.createPluginConfig() {
    val pluginConfig = TomlDecoder.decode<T>(
        serializer(),
        fakeFileNode,
        DecoderConf()
    ).apply {
        configLocation = this.toPath() // <---- bug
    }
}
```
