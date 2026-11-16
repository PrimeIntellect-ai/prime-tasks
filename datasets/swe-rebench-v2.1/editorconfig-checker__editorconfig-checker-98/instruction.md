Option to only disable indent_size check
It would be great to be able to just disable `indent_size` check but not `indent_style` check.

Currently it is only possible to `-disable-indentation` which means disabling `indent_size` and `indent_style` check.

Unfortunately there are many use cases where `indent_size` is not correct in complex files because every language handles some special cases differently. Also if you have _blank lines_  with just the correct number of spaces the check fails at the moment with "Wrong amount of left-padding spaces(want multiple of x)"

At the moment it is not possible in our workspace to fix all `indent_size` problems, but we would like to check the `indent_style` only but not the `indent_size`.

### Additional contract requirements

- The configuration must expose a boolean option `IndentSize` in the `Disable` section (JSON key `IndentSize` under `Disable`) that disables only the indent-size check while leaving the indent-style check active.
- When the indent-size check is active, a line whose leading spaces are not a multiple of the configured indent size must be reported with the error message `Wrong amount of left-padding spaces(want multiple of X)`, where `X` is the configured indent size.
- When the indent-size check is disabled, a line indented with spaces must not be reported for its indent size, while a line indented with tabs must still be reported as an indent-style error.
