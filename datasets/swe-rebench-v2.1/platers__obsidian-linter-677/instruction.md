FR: tidy footnotes
 for footnote, deliberately does *not* preserve the relation between key and footnote
maybe this plugin is a good reference:https://github.com/charliecm/obsidian-tidy-footnotes
Feature Request: Sherlock tidy-footnotes plugin?
I tried adding the command from the [tidy footnotes plugin](https://obsidian.md/plugins?id=obsidian-tidy-footnotes), as an extra custom command. However, it seems the plugin leaves extra blank lines at the end of a file if there are no footnotes in a note. even with the rule enforcing exactly one line break at the end of a file, somehow there are still the extra blank lines added at the end.

Theoretically, this could be an issue for the tidy footnotes plugin, but it does not look very active anymore. Moreover, the linter already has footnote linting rules, making the addition actually useful for users not looking for extra plugins. So the tidy footnote code could maybe be simply sherlocked for a simpler (and probably more bug free) user setup?
FR: re-index-footnotes Should not Overwrite Duplicate References
## Describe the Bug

`re-index-footnotes` doesn't seem to allow multiple references to the same footnote. Using footnotes for references will often lead to situations where the same footnote is used again and again, so the text has multiple of the same footnote reference. The Re-Index Footnotes rule simply changes the duplicate numbers into false, non-existent footnote references.

## How to Reproduce

Steps to reproduce the behavior:

1. Create a file with the following text:
```markdown
First,[^1] followed by the Second,[^2] and then the First[^1] again.

[^1]: First Reference
[^2]: Second reference
```
2. Run Linter with rule `re-index-footnotes` enabled.
3. The text above is changed to the following:
```markdown
First,[^1] followed by the Second,[^2] and then the First[^3] again.

[^1]: First Reference
[^2]: Second reference
```

## Expected Behavior

Leave the second `[^1]` reference alone, as it is a valid reference to the first footnote.

## Screenshots

If applicable, add screenshots to help explain your problem.

## Device

- [x] Desktop
- [ ] Mobile

### Additional contract requirements

- The `re-index-footnotes` rule renumbers footnote references and footnote definitions sequentially starting from 1, in the order in which the references first appear in the note.
- Footnote definitions are reordered so that they appear in the same order as their first reference in the note.
- Footnote definitions are consolidated at the end of the note.
- A note that contains no footnotes is left unchanged; no extra trailing blank lines are added.
- The tidy-footnotes functionality (re-indexing footnotes and consolidating footnote definitions) is provided by the linter itself, without requiring the external tidy-footnotes plugin.
