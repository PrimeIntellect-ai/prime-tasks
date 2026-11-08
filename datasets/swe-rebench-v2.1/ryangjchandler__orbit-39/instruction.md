Add a new `MarkdownJson` driver
This driver would work the same as the normal Markdown driver, but instead of using YAML as the front-matter, it would use JSON instead (YAML with brackets, lol).

### Additional contract requirements

- The generated `.md` file must use the same `---` front-matter delimiters as the normal Markdown driver, but the front matter between those delimiters must be valid JSON (rather than YAML).
- The model's attributes (for example `name`) must be stored as keys inside that JSON front matter.
- When an existing `.md` file is loaded, its JSON front matter must provide the model attributes, and its body must retain the normal Markdown driver's body behavior.
- Updating a model through this driver must persist the updated attributes and retain the normal Markdown driver's file lifecycle behavior.
