terminal_newline_linter
Add a linter which checks for terminal newlines in source.

Alternatively, we could extend/adjust `trailing_blank_lines_linter` to work for this case as well.

### Additional contract requirements

- The missing-terminal-newline check must be reported by the existing `trailing_blank_lines_linter`.
- For a source file without a terminal newline, the lint message must be exactly `Missing terminal newline.`
