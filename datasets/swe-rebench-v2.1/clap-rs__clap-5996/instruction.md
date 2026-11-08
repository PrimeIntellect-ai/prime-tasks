FR: Prefix argument long and short aliases in help output with -- and -
### Please complete the following tasks

- [x] I have searched the [discussions](https://github.com/clap-rs/clap/discussions)
- [x] I have searched the [open](https://github.com/clap-rs/clap/issues) and [rejected](https://github.com/clap-rs/clap/issues?q=is%3Aissue+label%3AS-wont-fix+is%3Aclosed) issues

### Clap Version

master

### Describe your use case

Currently, the help output shows aliases without leading `--` and `-`:

```
Options:
  -o, --opt <opt>  [short aliases: v]
  -f, --flag       [aliases: flag1] [short aliases: a, b, 🦆]
```

This makes the aliases appear like (sub)commands and hinder copy-pasting into the command line directly.

### Describe the solution you'd like

If the leading `--` and `-` are included, then the aliases will be formatted consistently with the arguments at the start of each line. It will also be easier to copy and paste the aliases correctly elsewhere:

```
Options:
  -o, --opt <opt>  [short aliases: -v]
  -f, --flag       [aliases: --flag1] [short aliases: -a, -b, -🦆]
```

### Alternatives, if applicable

Sticking with the status quo and relying on the user correctly prefixing long aliases with `--` and short aliases with `-` after identifying the aliases from the help output.

### Additional Context

_No response_
