UseDataClass: False positive with expected class
This class

```kotlin
expect class OAuthClientSettings() {
    val environment: Environment
    internal val authFlowFactory: CodeAuthFlowFactory
    internal val store: SettingsStore
}
```

triggers the following warning:

```
OAuthClientSettings.kt:9:14: The class OAuthClientSettings defines no functionality and only holds data. Consider converting it to a data class. [UseDataClass]
```

However, it is prohibited to create "expected" data classes:

```
Modifier 'expect' is incompatible with 'data'
```

## Your Environment
* Version of detekt used: 1.23.7
* Version of Gradle used (if applicable): 8.10.1
