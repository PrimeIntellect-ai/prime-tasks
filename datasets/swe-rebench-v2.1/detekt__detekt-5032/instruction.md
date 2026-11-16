Add ending line and column to `Location.kt`
External tooling, such SARIF or IDE may need ending lines and columns, in addition to the `SourceLocation`. They should be provided in `:detekt-api`.

_Originally posted by @BraisGabin in https://github.com/detekt/detekt/pull/5011#discussion_r911449557_

### Additional contract requirements

- `io.gitlab.arturbosch.detekt.api.Location` exposes a public `endSource: SourceLocation` property, readable via `getEndSource()`, holding the ending line and column of the represented code element.
- `Location.from(element: PsiElement, offset: Int = 0)` returns a `Location` whose `source` is the element's start `SourceLocation`, whose `endSource` is the element's end `SourceLocation`, whose `text` is the element's character range, and whose `filePath` identifies the containing file.
- The end `SourceLocation` is the exclusive end boundary: the position immediately after the element.
- The optional `offset` shifts both the computed start and end positions by that many characters.
