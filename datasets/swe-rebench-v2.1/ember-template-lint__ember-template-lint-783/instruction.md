Unable to use with VIM ALE plugin and other external tools
Pull Request #607 introduced a breaking change where tools that call ember-template-lint with a temporary file are unable to lint because the glob rules filter out the file.

Example usage: `ember-template-lint /tmp/random-dir/temporary-template.hbs`

A built in tool like [ALE](https://github.com/w0rp/ale) will execute this command because it needs to lint the unsaved buffer.

Possible solutions:

1. disable the glob rules if the argument is a file
2. disable the rule if the path is absolute
3. allow a flag to disable globbing
4. allow reading for stdin **best solution**

### Additional contract requirements

The command-line tool must support reading the template to lint from standard input. When it is invoked with no file path, or with a file path of `-` or `/dev/stdin`, it reads the template source from standard input and lints it. The `--filename <value>` option supplies the module path used for the standard-input content.

The command-line module at `bin/ember-template-lint.js` exports a function `_parseArgv(argv)` that parses an array of command-line argument strings into an object with a `positional` array and a `named` object. The recognized named flags are `--config-path <value>`, `--filename <value>`, `--quiet`, `--json`, and `--verbose`. Each recognized flag is stored in `named` under the keys `configPath`, `filename`, `quiet`, `json`, and `verbose`; flag-only options map to `true` and value options map to their string value. All arguments that are not recognized named flags are collected in `positional`. A solitary `--` stops named-argument parsing, and every remaining argument is placed in `positional`. Unrecognized flags are treated as positional arguments.
