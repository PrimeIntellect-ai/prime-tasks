plenary.scandir respect_gitignore doesn't work with more complex gitignores
For example:
- `**/bin`
- `!bin/asdf`

both currently will result in unexpected behavior

### Additional contract requirements

- With `respect_gitignore` enabled, a `**/bin` rule ignores matching `bin` directories at different path depths.
- A negated `!bin/asdf` rule re-includes a matching path even when an earlier rule ignores its parent `bin` directory.
