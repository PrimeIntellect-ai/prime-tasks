Unsigned integer literal is perhaps incorrectly marked as a MAGIC_NUMBER
## Describe the bug

Unsigned integer literal is perhaps incorrectly marked as a `MAGIC_NUMBER`

## Expected behavior

The rules for unsigned numeric values should be the same as the signed counterparts.

## Observed behavior

Unsigned integer literal is incorrectly marked as a `MAGIC_NUMBER`

```bash
[MAGIC_NUMBER] avoid using magic numbers, instead define
constants with clear names describing what the magic number means: 0U (cannot be auto-corrected)
```

## Steps to Reproduce

Assign an unsigned integer to a variable.

```kotlin
// this raises a MAGIC_NUMBER warning
var positiveNumber = 0U

// this does not have a warning
var otherNumber = 0
```

## Environment information
* diktat version: 1.0.1
* build tool (maven/gradle): gradle
* how is diktat run (CLI, plugin, etc.): gradle plugin
* kotlin version: 1.6.10
* operating system: MacOS 12.2.1
* link to a project (if your project is public): N/A
