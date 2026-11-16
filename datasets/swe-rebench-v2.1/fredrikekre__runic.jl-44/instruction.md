Alignment
Currently Runic destroys alignment because it is very stringent about spacing, for example
```julia
a  = 1
ab = 2
```
will be replaced with
```julia
a = 1
ab = 2
```
Doing this is of course a valid option (and what e.g. gofmt does).

The current rule is *a single space around operators*, but I wonder if relaxing it to *at least a single space around operators* would satisfy the "human need" to prettify things with alignment would be a good option. I think this would work in all situations where you typically align things.

### Additional contract requirements

Runic must support toggle comments that turn formatting off and on for a region of source
code, so that manually aligned code (such as the example above) can be retained instead of
being normalized.

- `# runic: off` turns formatting off and `# runic: on` turns it back on.
- For compatibility with JuliaFormatter, `#! format: off` and `#! format: on` are also
  recognized. The two styles cannot be mixed: an `off` comment of one style must be paired
  with an `on` comment of the same style.
- A toggle comment must be placed on its own line.
- The `off` and `on` comments must be on the same level in the syntax tree and must come in
  pairs.
- As an exception to the pairing rule, a top-level `# runic: off` comment turns formatting
  off for the remainder of the file, so a whole file can be excluded without adding a
  trailing `# runic: on` comment.
- Source text between a matching `off`/`on` pair is emitted unchanged, while source outside
  such regions is formatted normally.
