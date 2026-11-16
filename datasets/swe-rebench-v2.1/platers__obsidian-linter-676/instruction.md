Bug: move-footnotes-to-the-bottom Incorrectly Changes Order of Footnotes
## Describe the Bug

move-footnotes-to-the-bottom incorrectly changes the order of footnotes at the bottom when multiple footnote references to the same footnote are used.

## How to Reproduce

Steps to reproduce the behavior:

1. Enable the rule `move-footnotes-to-the-bottom`, and disable the rule `re-index-footnotes`.
2. Create a file with the following text:
```markdown
First,[^1] followed by the Second,[^2] and then the First[^1] again.

[^1]: First Reference
[^2]: Second reference
```
3. Run Linter.
4. The text above is changed to the following:
```markdown
First,[^1] followed by the Second,[^2] and then the First[^1] again

[^2]: Second reference
[^1]: First Reference
```

## Expected Behavior

Don't re-order the footnotes, leave them in order as 1, 2, ...

## Device

- [x] Desktop
- [ ] Mobile

### Additional contract requirements

- When applying the rule to this example, preserve the final period after `again.`.
