spaceAroundComma linter breaks on multiline definition
For very long definitions, as you might find with gradients, we'd like to be able separate each step on to a new line without the `spaceAroundComma` linter flagging it. Perhaps this needs to be an additional option?

Something like the following should be considered valid, in my opinion:
```less
.thing {
    background: linear-gradient(
        to bottom,
        transparent 0,
        transparent 25%,
        red 25%,
        red 75%,
        transparent 75%,
        transparent 0
    );
}
```

### Additional contract requirements

- Provide a boolean `allowNewline` option for this linter. When it is false, check newline-separated comma lists according to the configured spacing style; when it is true, do not report spacing violations for comma-separated items separated by newlines.
