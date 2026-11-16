change regex library
Negative lookaheads would be nice to have, and we don't need the performance benefits that `regex` gets from removing them.

### Additional contract requirements

- Regex selectors must support negative lookaheads: for example, `foo(?!bar)` matches `foo` only when it is not immediately followed by `bar`.
- For the invalid regex `\P{` in a select specifier, report the error text exactly as `regex parse error: Unicode escape not closed`.
- For the select specifier `# /\P{/`, place the diagnostic at ` --> 1:4` and render its caret line exactly as `  |    ^`.
