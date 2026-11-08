Bug: Re-Index footnotes also moves footnotes to the bottom
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

*Re-Index Footnotes* moves footnotes to the bottom, even when *Move Footnotes to the bottom* is unticked.

## How to Reproduce

Steps to reproduce the behavior:

1. In Linter settings, make sure *Re-index Footnotes* is turned on and *Move Footnotes to the bottom* is turned off.
2. Make a new document with the following text (without blockquotes):

```markdown
foo [^1]

[^1]: bar

foobar
```

3. Lint manually or via auto-lint on save.

## Expected Behavior

Expected behavior is that nothing should happen.

## Device

- [x] Desktop
- [x] Mobile (iOS)

### Additional contract requirements

- Re-Index Footnotes renumbers footnote identifiers to sequential numeric labels starting at `[^1]`, following the order in which the footnote definitions appear in the document. Identifiers that contain hyphens or other non-numeric characters (for example `[^numero]`, `[^num-1]`, `[^foo-bar]`, `[^hello-world]`) are renumbered the same way as numeric identifiers. Every reference to a footnote is updated to the same new label, and the footnote definitions remain in their original locations.
