flag completion for embedded dash command broken
```sh
example action -- --<TAB> # no results
example action -- -<TAB> # completes longhand flags
```

### Additional contract requirements

- For `example action -- -` and `example action -- --`, completions must return `--embedded-bool` with description `embedded bool flag` and style `style.Default`, `--embedded-optarg` with description `embedded optarg flag` and style `style.Yellow`, and `--embedded-string` with description `embedded string flag` and style `style.Blue`. The completion action must use `NoSpace('.')`, `Usage("action [pos1] [pos2] [--] [dashAny]...")`, and `Tag("flags")`.
- Also, when completing `example action -- embeddedP1 --embedded-optarg=`, return `eo1`, `eo2`, and `eo3` with prefix `--embedded-optarg=` and usage `embedded optarg flag`; when completing `example action -- embeddedP1 --embedded-string ""`, return `es1`, `es2`, and `es3` with usage `embedded string flag`. For `example action p1 --styled-values second p2 -- embeddedP1 --embedded-string es1 ""`, return `embeddedPositional2` and `embeddedP2` with usage `action [pos1] [pos2] [--] [dashAny]...`.
