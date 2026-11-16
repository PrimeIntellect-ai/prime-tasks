How do you run just one test?
The `pnpm test` command has some abstraction which makes using mocha flags directly inaccessible

### Additional contract requirements

Provide a separate `pnpm mocha` command that accepts Mocha filtering options directly (for example, a grep filter) and runs only matching tests, without requiring those options to pass through the `pnpm test` wrapper.
