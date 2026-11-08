sprintf linter
I'm thinking of a `sprintf` linter that extracts all `sprintf(...)` calls and checks if the number of supplied arguments is consistent with the number of format placeholders in the format string when the format string is a string literal (rather than a symbol or call).

If the supplied argument is an atomic value, it could also check if its type is consistent with the format at the corresponding position.

### Additional contract requirements

The linter is available as the callable API `sprintf_linter`.
