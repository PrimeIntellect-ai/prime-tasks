flag completion for embedded dash command broken
```sh
example action -- --<TAB> # no results
example action -- -<TAB> # completes longhand flags
```

### Additional contract requirements

- When completing an empty argument after `example action --`, return the positional candidates `embeddedP1` and `embeddedPositional1` with usage `action [pos1] [pos2] [--] [dashAny]...`.
- For current arguments `-` and `--`, return `--embedded-flag` with description `embedded flag`, `NoSpace('.')`, usage `action [pos1] [pos2] [--] [dashAny]...`, and tag `flags`.
