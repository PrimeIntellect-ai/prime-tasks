`KotlinParseException` in [STRING_CONCATENATION]
## Describe the bug
```kotlin
fun foo() {
    "File is" + if (fileInfo.isExecutable) "regular" else "executable"
}
```

```
org.cqfn.diktat.ruleset.utils.KotlinParseException: Text is not valid: [""Click to mark file " + if (fileInfo.isExecutable) "regular" else "executable""
```

## Observed behavior
Diktat doesn't support concatenation of string and `if` expression

## Environment information
* diktat version: 1.0.0-rc.3

### Additional contract requirements

- When fixing `val myTest26 = "my string " + if (true) "1" else "2"`, convert it to `val myTest26 = "my string ${if (true) "1" else "2"}`.
