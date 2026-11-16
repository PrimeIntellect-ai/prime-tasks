Success code returned on missing packages
I was totally confused by output of pipdeptree when I tried to call it with `pipdeptree -p ansiblelint`, as it listed not deps and returned as success.

It was my mistake to mention module name instead of correct packaga name `ansible-lint` but clearly returning 0 is a bug, as a missing package should clearly return an error.

### Additional contract requirements

- `PackageDAG` (importable from `pipdeptree._models`) exposes `filter_nodes(include, exclude)`, where `include` is a list of fnmatch patterns or `None` and `exclude` is a set of fnmatch patterns or `None`. Patterns are matched case-insensitively against package keys, and passing `None` for a filter disables that filter.
- If a pattern appears in both `include` and `exclude`, `filter_nodes` raises `AssertionError`.
- If `include` is provided and one or more of its patterns match no existing package, `filter_nodes` raises `ValueError` whose message is `No packages matched using the following patterns: <patterns>`, listing the non-matching patterns in the order they were given.
- The command-line interface accepts `-w fail` (equivalently `--warn fail`). When `-p`/`--packages` is given patterns that match no installed package, the command writes a message to stderr and exits with a non-zero status.
