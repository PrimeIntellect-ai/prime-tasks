Add support for printing out the description as part of a field
The field defintions in openapi can have a description. It would be nice, if this description can be printed in the generated Go-code as well.

### Additional contract requirements

- When an OpenAPI operation parameter declares a `description`, the generated Go struct field for that parameter is preceded by a Go comment containing the description text. Each line of the description is rendered as a comment line prefixed with `// `.
- Add a public function `StringToGoComment(in string) string` in package `github.com/deepmap/oapi-codegen/pkg/codegen`. It renders an arbitrary string as a Go comment block: every line of the input is prefixed with `// `, whitespace within each line is preserved, Windows (`\r\n`) and Mac (`\r`) line endings are normalized to Unix (`\n`), and a trailing newline does not produce a trailing empty comment line.
