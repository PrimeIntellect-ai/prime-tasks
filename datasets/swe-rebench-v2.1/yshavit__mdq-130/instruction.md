exit 1 if no items found
also, add `--quiet`/`-q` flag, similar to Grep's

### Additional contract requirements

- Add a public function `run_in_memory(cli: &Cli, contents: &str) -> (bool, String)` in the crate root (`src/lib.rs`). The boolean is `true` when the query matched at least one element and `false` otherwise. The string is the formatted output, and is empty when there are no matches or when `--quiet` is set.
- `--quiet`/`-q` suppresses output to stdout but does not change the exit status: the process still exits 0 when at least one item is found and 1 when none are.
