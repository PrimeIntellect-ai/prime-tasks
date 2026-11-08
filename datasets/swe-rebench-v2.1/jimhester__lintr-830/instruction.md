Linter for space needed after right parenthesis of function symbol formals
Just notice that there seems to be no linter that complains about the following code

```r
function(x)x + 1
```

where a space is needed between `function(x)` and `x + 1`.

### Additional contract requirements

- The linter is exposed as `paren_body_linter()`, which takes no arguments and returns a linter usable with `lint()` and `expect_lint()`.
- A lint is reported when a function body immediately follows the closing parenthesis of its formal arguments with no whitespace between them (for example `function(x)x + 1`). The lint is reported on the line where the body starts.
- No lint is reported when there is a space between the closing parenthesis and the body (for example `function(x) x + 1`), or when the body starts on a following line.
- Symbols following the closing parenthesis of a function call, and text inside comments, are not reported.
