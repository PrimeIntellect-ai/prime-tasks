Bracket line setting for JSX
In a similar spirit to the `jsxElement.spaceBeforeSelfClosingTagSlash` rule, it would be great to have a rule similar to [Prettier's `bracket-line`](https://prettier.io/docs/en/options.html#bracket-line) for formatting non-self closing JSX elements :)

### Additional contract requirements

The behavior is exposed through the `jsx.bracketPosition` configuration key. It accepts the string values `maintain`, `sameLine`, and `nextLine` (default `nextLine`). It controls the position of the end angle bracket (`>`) of a non-self-closing JSX element when the element's attributes span multiple lines:

- `maintain`: keeps the end angle bracket on the line it was originally on.
- `sameLine`: forces the end angle bracket onto the same line as the last attribute.
- `nextLine`: forces the end angle bracket onto its own line following the last attribute.
