ktfmt* tasks are not configuration-cache compatible
## 🐛 Describe the bug
ktfmt* tasks are not configuration-cache compatible because `KtfmtBaseTask.scope` is non-serializable

## ⚠️ Current behavior
Build fails because of configuration cache issues

## ✅ Expected behavior
Build should succeed

## 💣 Steps to reproduce
Run `./gradlew :example:ktfmtFormat --configuration-cache`

### Additional contract requirements

- Running a ktfmt task twice with `--configuration-cache` must succeed both times, and the second run must reuse the configuration cache (Gradle reports `Reusing configuration cache.`).
