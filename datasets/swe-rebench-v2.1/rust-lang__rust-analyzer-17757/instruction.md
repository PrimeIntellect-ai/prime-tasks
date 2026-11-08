Assist to toggle between delimiters for macro calls
Simple assist that goes from `foo!()` -> `foo!{}` -> `foo![]` -> `foo!()` when on one of the two delimiters.

### Additional contract requirements

- The assist is named `toggle_macro_delimiter`.
- When the delimiters are changed to braces, a trailing semicolon after the macro call is removed.
- When the delimiters are changed to brackets or parentheses, a trailing semicolon after the macro call is preserved.
