can not use "operator UpdateBuilder.set" to set a value of a nullable composite column
prior to version 0.37.1 of kotlin-exposed, there was this function in UpdateBuilder.kt:
[HIDDEN]

in 0.37.1 its signature was changed to:
[HIDDEN]

is there a compelling reason for S to be a subtype of [HIDDEN] ?
with this change, i am no longer able to update the value of a nullable composite column with the help of this function, which was possible with version 0.36.1 and earlier.

### Additional contract requirements

- `UpdateBuilder.set` must allow callers to assign `null` to a nullable composite column when building a statement, including an update.
