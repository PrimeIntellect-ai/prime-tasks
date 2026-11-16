super eager `help` command execution
I'm not sure if I'm doing something wrong here, but the `help` command is being executed if the word `help` is anywhere in the arguments text. I'm using it for a Slack app. My parser is configured like so:

```
const parser = require('yargs')
  .usage('Usage: /<command> <args>')
  .commandDir('../commands')
  .demand(1)
  .strict()
  .help()
  .alias('help', 'help?')
  .alias('help', 'h')
```

I expect `help` to run in only two cases: If a user does `/help?` or if they do `/<command> --help`, but not if there's just `/<command> something something help something`, which is currently triggering help text. Am I misconfiguring something or misunderstanding how the help auto command works?

### Additional contract requirements

- Help output is triggered when the configured help option name (default `help`) or an alias longer than one character is the final positional argument. A one-character configured help name does not trigger help as a positional command.
- A single-character alias of the help option does not act as a positional help command.
- A qualifying help command token that is not the final positional argument does not trigger help output.
- The help option itself, such as `--help` or `--info` when configured with `.help('info')`, continues to trigger help output.
