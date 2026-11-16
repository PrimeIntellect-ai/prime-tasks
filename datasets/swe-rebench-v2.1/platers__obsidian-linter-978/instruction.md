FR: Ensure single space after blockquote `>` angle brackets
## Is Your Feature Request Related to a Problem? Please Describe.

I have one small issue I've just noticed related to blockquotes and our conversations in (#910). Not sure if it's intentional or not, and apologies if it has already been mentioned:

```markdown
>  Text
```

Doesn't lint as:

```markdown
> Text
```

Is there a reason why the >=2 spaces don't get reformatted as a single space? Maybe it's a compromise of some sort? Perhaps it's because not all people use spaces after blockquote angle brackets, e.g. `>> Text` or even `>>Text`.

The problem exists with plain lines beginning with a space too which lead me to find your options to "Remove space around/before/after characters". These could probably mitigate it (but as noted, whilst also risking Markdown formatting in some cases).

I mentioned a similar issue with tables, unsure if any relation: #951

## Describe the Solution You'd Like

I guess my only issue then is that maybe removing >1 spaces could be a distinct rule for blockquotes since we already have the "Space after list markers" option.

Consider adding "Space after _blockquote_ markers" to ensure a single space. Or more flexibly, make it a choice between ensuring no spaces (e.g. `>Text`), no spaces but one after final `>` (e.g. `>> Text`), and ensure space after each `>` (e.g. `> > Text`). If a blockquote `>` is followed by only whitespace, "Removes extra spaces after every line." should trim it.

You've recently done a lot to fix blockquote issues, so I don't expect you to be too enthusiastic at this time, but this issue is here for if/when that time comes.

Thanks!

### Additional contract requirements

- When `style` is `no space`, preserve whitespace used to indent a list marker after the blockquote prefix; do not remove it while removing spaces after blockquote markers.
