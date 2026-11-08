Bug: Smart quotes get applied in Markdown image links
- [x] I have verified that I am on the latest version of the Linter

## Describe the Bug

Markdown image links do not get ignored, even though regular Markdown links are.

## How to Reproduce

Example to reproduce issue with

``` markdown
![link](https://test.it 'Test title')
```

## Expected Behavior

It should ignore the quotes, as they exist within a Markdown style image link.

## Device

- [x] Desktop
- [ ] Mobile

## Additional Context

I have made [a failing test](https://github.com/platers/obsidian-linter/commit/5818d0582cd6b7d97c70de1d91fe55593e071107), but have not been able to find the cause.

It seems that [the correct exceptions are already applied](https://github.com/platers/obsidian-linter/blob/952bba9d7b6a4f084d68ffdd469bd89e785206b2/src/rules/quote-style.ts#L32) and that [the link exception](https://github.com/platers/obsidian-linter/blob/952bba9d7b6a4f084d68ffdd469bd89e785206b2/src/utils/ignore-types.ts#L33)’s [RegEx already properly checks for the optional `!`](https://github.com/platers/obsidian-linter/blob/952bba9d7b6a4f084d68ffdd469bd89e785206b2/src/utils/regex.ts#L15) which makes it an image link.

Yet it fails on image links, but not on regular links.
