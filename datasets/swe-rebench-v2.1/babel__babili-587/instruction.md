Don't use path.replaceWith() with a source string, [HIDDEN]
ERROR in unknown: Don't use `path.replaceWith()` with a source string, [HIDDEN]

Seems to be the result of this change :
https://github.com/babel/babili/pull/543/files

### Additional contract requirements

- The constant-folding transform must complete without error and return its input unchanged for inputs containing `"foo".toString();`, `["foo", "bar"].toString();`, `({}).toString();`, `"foo".toString;`, `["foo", "bar"].toString;`, and `({}).toString;`.
