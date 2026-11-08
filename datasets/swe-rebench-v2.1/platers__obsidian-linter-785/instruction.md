Bug: re-index-footnotes & move-footnotes-to-the-bottom can cause Obsidian freeze with footnote wrapping
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Linting a file with re-index-footnotes or move-footnotes-to-the-bottom will cause Obsidian to freeze, I think indefinitely, if a reference is wrapped in two of its footnotes -- at least that's as far as I've been able to zoom into the cause. It didn't spit out any logs when it happened.

## How to Reproduce

Steps to reproduce the behavior:

1. Create a new file in a vault with contents:

```markdown
[^2]: a

a[^2]

[^2]: b
```

2. On macOS (I haven't tested elsewhere), open the file in the Obsidian app
3. Lint the file with re-index-footnotes or move-footnotes-to-the-bottom enabled
4. Notice that Obsidian freezes

## Expected Behavior

If re-index-footnotes is enabled: user notification that re-index-footnotes doesn't work if there is more than one footnote for a key.

If move-footnotes-to-the-bottom is enabled: footnotes are moved to the bottom of the file as expected.

## Device

- [x] Desktop
- [ ] Mobile

### Additional contract requirements

- When re-index-footnotes is enabled and a footnote key has more than one footnote definition, the rule must not silently produce output: it raises an error so that the linter can notify the user that re-indexing does not work in that case.
