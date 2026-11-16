Conflicting TOO_MANY_BLANK_LINES and BRACES_BLOCK_STRUCTURE_ERROR with empty block
## Describe the bug
```kotlin
foo {

}
```
in check mode produces two errors:
```
[TOO_MANY_BLANK_LINES] too many consecutive blank lines: do not put newlines in the beginning of code blocks
[BRACES_BLOCK_STRUCTURE_ERROR] braces should follow 1TBS style: no newline before closing brace
```
in fix mode everything is fine, because, I suppose, the first inspection removes the blank line and the second restores it.

## Environment information
* diktat version: 0.4.1

### Additional contract requirements

- For a multiline empty lambda, emit `EMPTY_BLOCK_STRUCTURE_ERROR` with the message `${EMPTY_BLOCK_STRUCTURE_ERROR.warnText()} do not put newlines in empty lambda`; in fix mode, format the lambda as `{ }` (for example, `val y = listOf<Int>().map { }`).
- - Report this warning at line 2, column 30.
