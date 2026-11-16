Add the receiver name length check to `rule.receiver-naming`
**Is your feature request related to a problem? Please describe.**
I would like to check the length of receiver variable names.

**Describe the solution you'd like**
Add the receiver variable name length check to the `receiver-naming` rule.

**Describe alternatives you've considered**
I created a [linter](https://github.com/ytnsym/receivernamelen), but it seemed like it would be better to improve the `receiver-naming` rule.

**Additional context**
https://github.com/golangci/golangci-lint/pull/5007#issuecomment-2350457699

### Additional contract requirements

The `receiver-naming` rule may be configured with a positive integer `maxLength` argument specifying the maximum allowed number of characters in a receiver variable name. When this limit is configured, the rule must report receiver names whose length exceeds it; names at or below the limit must not be reported for length. When no length limit is configured, the rule must not report receivers based on their length.
