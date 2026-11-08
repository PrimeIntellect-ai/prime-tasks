error: HardFailure: HardFailure()
This is low-priority, but I'm guessing the title string shouldn't show up in diagnostics.  Reproduce with:
```
typealias X: Y = Z
```

### Additional contract requirements

- Parsing the source `typealias X: Y = Z` must fail, and the error must be reported at the line of the `typealias` declaration with the message `declaration requires definition`.
- That error message must not include the title string `HardFailure` or any other internal title.
