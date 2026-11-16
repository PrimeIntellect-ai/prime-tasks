Add support for a --quiet flag for the spec command
The `flask spec` command currently always prints output to stdout. In cases where the output is being directed to a file, a `--quiet` command option (or similar) would be useful to pipe the results to the output file without printing them as well.

### Additional contract requirements

- The `flask spec` command accepts a `--quiet` flag that suppresses printing the spec to stdout.
- When `--quiet` is combined with an output file, the spec is still written to that file while nothing is printed to stdout.
