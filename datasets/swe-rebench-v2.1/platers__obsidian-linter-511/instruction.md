Bug: Linting a file with a header like [[Test]] creates an error on the second lint with Title option enabled
## Describe the Bug

Reference: #449

If I lint a file with

# [[Test]]

two times I get the following error:

```
Obsidian Linter] Lint File Error in File 'Example/Test.md':
YAMLException: bad indentation of a mapping entry (9:3)

  6 | language: de
  7 | Vault: Privat
  8 | title: [[Test]]
  9 |   - [Test]
--------^
 10 | tags:
 11 | aliases: [[[Test]]]
```
So I guess there is still something to be corrected to support links as headers

Let me know if you need more information or an example file.

### Additional contract requirements

- When YAML Title or YAML Title Alias writes a title or alias containing a Markdown link or Obsidian wikilink, it must convert the link to its displayed text, removing the link markup and destination. For example, `This is a [Heading](test heading.md)` and `This is a [[Heading]]` become `This is a Heading`, and `[[Heading]]` becomes `Heading`. This applies both to values derived from the first H1 and to existing YAML `title`, `aliases`, and `linter-yaml-title-alias` values.
