BodyLike.schemaContent() always returns null
in v0.8 mode

### Additional contract requirements

In v0.8 mode, when a body declares a schema by referencing a top-level schema declaration, `schemaContent()` must expose that schema's text. When a body declares a schema inline, `schemaContent()` must expose the inline schema text.
