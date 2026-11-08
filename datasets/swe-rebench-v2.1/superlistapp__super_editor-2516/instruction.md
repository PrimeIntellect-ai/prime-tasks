[Attributed Text] - Fix copyAndAppend() and other places not accounting for placeholders
In a client app I discovered that when calling `AttributedText.copyAndAppend(moreText)` it can throw an exception when a placeholder is in the originating `AttributedText`. This is because `copyAndAppend()` (and maybe other methods) are still using [HIDDEN] so that we account for placeholders.

Make that change, add relevant tests, cut a new release.

### Additional contract requirements

- `copyAndAppend(moreText)` must successfully append text when the originating `AttributedText` contains placeholders, preserving its existing attributions and placeholder positions.
- Attribution queries must correctly report spans whose ranges extend through placeholders beyond the underlying plain-text length.
- Collapsed attribution spans must correctly account for placeholder positions, including placeholders beyond the underlying plain-text length.
