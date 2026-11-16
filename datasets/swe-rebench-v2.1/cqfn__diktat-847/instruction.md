autofix for `WRONG_ORDER_IN_CLASS_LIKE_STRUCTURES` removes values from enum class
## Describe the bug

Applying autofix for the rule `WRONG_ORDER_IN_CLASS_LIKE_STRUCTURES` via the Gradle plugin (`./gradlew diktatFix`) can result in values being removed from an enum class such as the following:

```
enum class Enum {
  FOO,
  BAR,
  ;

  companion object
  fun f() {}
}
```

## Expected behavior

The function definition and the companion object should be swapped, resulting in the following file:
```
enum class Enum {
  FOO,
  BAR,
  ;

  fun f() {}
  companion object
}
```

The above is passes `./gradlew diktatCheck`.

## Observed behavior

The autofix removes the values from the enum class, resulting in the following file:

```
enum class Enum {
  fun f() {}

  companion object
}
```

## Steps to Reproduce

Run autofix against a project containing an enum class such as the one described above, e.g. via `./gradlew diktatFix` when using the Gradle plugin.

## Environment information
* diktat version: 0.5.0
* build tool (maven/gradle): Gradle, v6.8.3
* how is diktat run (CLI, plugin, etc.):
* kotlin version: 1.4.32 (kotlin-compiler-embeddable-1.4.30)
* JDK: Corretto-11.0.7.10.1
* operating system: GNU/Linux; Ubuntu 20.04
