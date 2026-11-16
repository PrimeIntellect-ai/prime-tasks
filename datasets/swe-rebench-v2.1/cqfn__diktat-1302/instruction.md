ENUMS_SEPARATED fails to converge if last enum entry has comment on same line
## Describe the bug
The following code fails to converge with the ENUMS_SEPARATED inspection:
```
enum class Foo {
    A,
    B,
    C // some comment
}
```

It tries to ensure that the last enum entry has a trailing comma, but it is added at the end of the line.
Since the comma is part of the comment, this step will repeat and fails to converge.

## Expected behavior
Independently of whether a comment on the same line is considered a good style or not, the inspection should converge even with a comment present.

## Environment information
* diktat version: 1.1.0
* build tool (gradle): 7.4.2
* how is diktat run (CLI, plugin, etc.): spotless
* kotlin version: 1.6.20
* operating system: windows/ubuntu

### Additional contract requirements

- When fixing an enum whose last entry has a same-line comment, put the trailing comma before the comment and keep the comment on the same line; for example, `C // some comment 11` must become `C, // some comment 11`.
