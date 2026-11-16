FR: Support Obsidian-style comment for inline linter toggle
## Is Your Feature Request Related to a Problem? Please Describe.

Writing HTML comments (`<!-- -->`), aside from being tedious normally, is especially annoying when using software or plugins that attempt to auto-correct successive hyphens and other characters into distinct typographical marks. For example, [Smart Typography](https://github.com/mgmeyers/obsidian-smart-typography) ([view in Obsidian](https://r.0xyz.com/?to=obsidian%3A%2F%2Fshow-plugin%3Fid%3Dobsidian-smart-typography)) makes typing an HTML comment look something like this:
`<!----` *`<BS>`* `linter-disable----` *`<BS>`* `>` *`<BS>`*

Is that not a problem of this plugin? Absolutely. But only looking at HTML comments ignores Obsidian's commenting syntax which could be used as an alternative, for more reasons than just this one.

## Describe the Solution You'd Like

Allow for `%%linter-(en|dis)able%%` as an alternative.

## Describe Alternatives You've Considered

Use templates instead of writing out the comment.

## Additional Context

#1122

### Additional contract requirements

The Obsidian-style inline toggle may be written either compactly as `%%linter-disable%%` / `%%linter-enable%%` or with whitespace between the `%%` delimiters and the toggle text, e.g. `%% linter-disable %%` / `%% linter-enable %%`. Both spellings must be recognized as equivalent to the corresponding HTML comment toggle (`<!-- linter-disable -->` / `<!-- linter-enable -->`).
