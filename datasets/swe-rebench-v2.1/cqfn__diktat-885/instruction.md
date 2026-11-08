FP for gradle scripts
## Describe the bug
```kotlin
// build.gradle.kts
version = "0.1.0-SNAPSHOT"

// settings.gradle.kts
rootProject.name = "save"
```
should be allowed, but diktat suggests to wrap them in `run`.

 - `HEADER_MISSING_IN_NON_SINGLE_CLASS_FILE` shouldn't trigger for gradle scripts (should for regular kts files)

## Environment information
* diktat version: 0.5.0
