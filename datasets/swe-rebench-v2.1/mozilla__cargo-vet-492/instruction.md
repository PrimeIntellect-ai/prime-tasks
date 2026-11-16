Violations should not appear in imports.lock if the crate is not used
Right now on m-c, cargo-vet wants to pull in a violation entry from embark for a crate (`epaint`) we don't use. I'm guessing that when we modified `imports.lock` to be more selective we missed violations somehow. We should fix that.

### Additional contract requirements

- The removal of violations for crates that are not used in the dependency graph
  applies when imports are pruned (the default behavior). When import pruning is
  disabled, existing violation entries are preserved.
