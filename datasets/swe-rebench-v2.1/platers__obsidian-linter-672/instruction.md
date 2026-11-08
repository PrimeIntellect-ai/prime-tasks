Bug: Consecutive Blockquotes Merging
## Describe the Bug

After updating to 1.11.0, consecutive blockquotes are merged, the empty lines in between not serving as separation anymore but replaced by ">".

Suspect due to https://github.com/platers/obsidian-linter/pull/658

## How to Reproduce

Example to reproduce issue with

``` markdown
> [!quote] Title 1
> The quote 1

> [!quote] Title 2
> The quote 2
```

## Expected Behavior

Keep empty lines between consecutive blockquotes.

Expected output: No change

What I got:
``` markdown
> [!quote] Title 1
> The quote 1
>
> [!quote] Title 2
> The quote 2
```
