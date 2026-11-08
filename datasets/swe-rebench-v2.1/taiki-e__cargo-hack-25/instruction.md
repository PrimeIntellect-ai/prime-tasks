request: Add a `--skip` subcommand
## Motivation

`--feature-powerset` was added recently and it has been really helpful.
Unfortunately, if there is a feature that doesn't need to be tested in the
combinations it's not possible to skip. Each additional feature that is tested
in the powerset doubles the run-time so it can be costly as the number of
features grows.

## Solution

Add a `--skip` subcommand that can be paired with `--each-feature` or
`--feature-powerset`. The latter subcommands would filter out any features
passed in `--skip` before running their own logic.

I wanted to open the issue before sending in a PR incase @taiki-e had any
thoughts? If this is something you are okay with adding, I can send in a quick
change to add it. It should be fairly straightforward.

### Additional contract requirements

- When `--skip` is used without either `--each-feature` or `--feature-powerset`, the error output must contain `--skip can only be used with either --each-feature or --feature-powerset`.
