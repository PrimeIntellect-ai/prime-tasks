RedundantSuspendModifier false positive with expect/actual class
## Expected Behavior

If an `expect class` has functions with `suspend` in the signature, I shouldn't get a violation for having `suspend` in the `actual class` even if no suspending functions are called.

## Observed Behavior

I do get a violation.

## Steps to Reproduce

```kotlin
public expect class ThemeSettingStorage {
  public suspend fun load(): ThemeSetting?
  public suspend fun store(setting: ThemeSetting)
}

public actual class ThemeSettingStorage {
  public actual suspend fun load(): ThemeSetting? = ThemeSetting.System

  public actual suspend fun store(setting: ThemeSetting) {
  }
}
```

## Your Environment
* Version of detekt used: 1.23.5
* Version of Kotlin used: 1.9.22
* Version of Gradle used (if applicable): 8.6
* Operating System and version: Ubuntu 22.04
