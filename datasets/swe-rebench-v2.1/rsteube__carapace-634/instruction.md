zsh: zstyle list-colors
- `compadd`: ansi escape sequences are stripped
- `compadd -l`: ansi escape sequences work
- `export ZSH_COLOR=${style}`: does not work
- `export ZSH_COLOUR=${style}`: does work, but only if no default `list-colors` is set with `zstyle`
- `zstyle ':completion:*' list-style '${style}`: works, but values are only highlighted after second `<tab>` and changes the default
- `zstyle ":completion:*:*:example:*" list-colors "${style}"`: does not work
- `zstyle ":completion:${curcontext}:*" list-colors "${style}"`: does not work
