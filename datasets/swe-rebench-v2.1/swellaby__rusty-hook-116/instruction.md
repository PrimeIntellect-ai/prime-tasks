Allow multiple commands for a given Git hook
## Description

I started using `rusty-hook` recently. I have everything configured now, but I can't execute multiple commands for a given Git hook, for instance:

```toml
[hooks]
pre-commit = "cargo fmt -- --check"
pre-push = [
  "cargo test --all",
  "cargo build --release"
]

[logging]
verbose = true
```

That's what I'm trying to achieve, but the configuration file is invalid. Is it possible to allow multiple actions/commands when a given Git hook is triggered?

## Value

Sometimes we would like to do several actions/things when a Git hook is triggered. Currently that's not possible, or at least in the way I would expect it to work. I can join the commands I guess, but it would be clear to accept an array and execute them.
