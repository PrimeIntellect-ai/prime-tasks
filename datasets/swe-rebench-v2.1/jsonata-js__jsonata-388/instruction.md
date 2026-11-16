$parseInteger fails with "#" picture string
I'm doing this from Node Red, which is using JSONata 1.6, so this may have been fixed, but I cannot confirm.

`$parseInteger("50", "#")` produces the following error:

`Invalid JSONata expression: matchSpec.parse is not a function`.

After some investigation I found `$formatInteger(50, "#")` is not handled, but produces a better error message:

`Invalid JSONata expression: Formatting an integer as a sequence starting with "#" is not supported by this implementation`

This looks like error D3130, and since this error still exists in 1.7, I'm guessing the other error still occurs too. Is it possible to improve the error message?

### Additional contract requirements

For `$parseInteger("50", "#")`, the D3130 diagnostic message is `Formatting or parsing an integer as a sequence starting with "#" is not supported by this implementation`.
