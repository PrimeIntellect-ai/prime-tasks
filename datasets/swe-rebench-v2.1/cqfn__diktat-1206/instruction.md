Adapt `WHEN_WITHOUT_ELSE` according to new features of Kotlin 1.6
Now our 'generated else block' is treated as a compiler warning sometimes:
```kotlin
when (state.confirmationType) {
                ConfirmationType.NO_BINARY_CONFIRM, ConfirmationType.NO_CONFIRM -> submitExecutionRequest()
                ConfirmationType.DELETE_CONFIRM -> deleteProjectBuilder()
                else -> {
                    // this is a generated else block
                }
            }
```
causes
```
w: 'when' is exhaustive so 'else' is redundant here
```

### Additional contract requirements

- Do not add an `else` branch when Kotlin 1.6 considers a `when` exhaustive, avoiding the redundant-`else` compiler warning.
- For a non-exhaustive `when` statement, preserve the missing-`else` diagnostic or insert the branch in automatic-fix mode.
