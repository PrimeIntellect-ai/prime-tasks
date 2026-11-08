Optimizer: Ungroup transform does not merge adjacent Alternatives
At the moment, when the Ungroup transform removes groups, it does not merge adjacent Alternatives, leading to an AST that should not naturally happen on parsing.

For example: `(?:abcd)(?:abcd)` is an Alternative containing two Groups.
When the Ungroup transform runs, it transforms it to an Alternative of two Alternatives. This gives the correct result when generated as a string or a regexp, but the AST should not contain this.

This issue leads to following transforms misinterpreting the AST:
`(?:abcd)(?:abcd)` -> `abcdabcd` -> `abcd{2}` instead of `(?:abcd){2}`.
