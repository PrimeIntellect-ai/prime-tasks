new rule: identical-branches
An `if-then-else` conditional with identical implementations in both branches is an error.
I've developed a prototype of a rule that detects such cases (testing the rule against real code has [already found bugs](https://github.com/gogo/protobuf/issues/687))

### Additional contract requirements

- The rule is exposed as the exported type `IdenticalBranchesRule` in package `rule` (import path `github.com/mgechev/revive/rule`).
- `IdenticalBranchesRule.Name()` returns the string `identical-branches`.
- `IdenticalBranchesRule.Apply(file *lint.File, _ lint.Arguments) []lint.Failure` returns a failure for each `if` statement whose then-branch and else-branch are identical.
- The failure message reported for matching branches is `both branches of the if are identical`.
