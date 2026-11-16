Do not set boolean to `false` if flag is not in args
Currently when defining a `boolean` option, without specifying its default value, if the user doesn't set the corresponding arg the value is set to `false`.

Therefore its impossible to know if users set the flag to `false` or this they just omitted it.

This is problematic in situation in which you want to merge the options returned by `yargs-parser` with another object options (from a config file for example) with `Object.assign` or similar.
Typically you would merge options so the CLI args take precedence  over the config file. So users can specify their config and override it in development mode by passing an option to the cli.

In such situation, if the user do not pass the flag in the CLI, the merged options will always have `false` for this flag, as `yargs-parser` option have it set to false and it override what's in the config.

Ideally the value of a boolean flag should be `undefined` when the user doesn't pass the flag in the CLI.

Would be open to a PR that implement such behavior?
