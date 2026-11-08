False negative for companion object in UndocumentedPublicClass
## Steps to Reproduce
```kotlin
public object PublicObject

public class PublicClass {

	public companion object;
}
```

Configuration:
```gradle.kts
detekt.allRules = true
// Does not contain relevant lines, just a few rules deactivated or fine tuned.
detekt.config.from(rootProject.file("config/detekt/detekt.yml"))
dependencies { detektPlugins(libs.detekt.rules.libraries) }
```

## Observed Behavior
```console
src\main\kotlin\com\example\PublicTest.kt:21:15: PublicObject is missing required documentation. [UndocumentedPublicClass]
src\main\kotlin\com\example\PublicTest.kt:23:14: PublicClass is missing required documentation. [UndocumentedPublicClass]
```

## Expected Behavior
The 2 findings are fine, but there are 3 public classes in the above code:
 * `PublicObject`
 * `PublicClass`
 * `PublicClass.Companion`

So the false negative is the companion object.

## Context
I'm relying on detekt to ensure that all my public API surface is documented.

 * Related: https://github.com/detekt/detekt/issues/7218

## Your Environment
<!-- Include as many relevant details about the environment you experienced the bug in -->
* Version of detekt used: 1.23.5
* Version of Gradle used (if applicable): 8.7
* Gradle scan link (add `--scan` option when running the gradle task): N/A
* Operating System and version: Windows 10 / GitHub Actions Ubuntu 22.04
* Link to your project (if it's a public repository): N/A
