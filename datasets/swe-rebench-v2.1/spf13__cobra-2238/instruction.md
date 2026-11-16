Feature request: Set a default completion function
In my experience, not many flags actually require completion of files.

Some have dynamic completions, but a great deal of them take free-form string parameters where no completion can be offered.
Unfortunately, the default completion for a flag with no completion function in Cobra is file completion.
This forces me to register a `cobra.NoFileCompletions` for each flag of that category.

As an example, completion for `docker run` has 56 flags where no meaningful FlagCompletionFunc exists.
In a first attempt, I registered 56 handlers with `cmd.RegisterFlagCompletionFunc("flag-name", cobra.NoFileCompletions)` just to silence their file completion.
Following a hint of @thaJeztah, I replaced them with a programmatically installed default handler, see [here](https://github.com/docker/cli/commit/06260e68f3686a0368284a8ce9b910e056bb523b#diff-50fe347eb4bdafebc190aa42b2caa34b089a538cd444b8a151a763372e93c0cf).

I would very much welcome a solution in Cobra, where I can set a default handler on command level, something like

```go
cmd.CompletionOptions.DefaultCompHandler = cobra.NoFileCompletions
```

With this feature, I'd only have to define the completion functions for flags that actually have meaningful completions.

/cc @thaJeztah

### Additional contract requirements

The default completion behaviour is configured as a default shell-completion directive on a command's completion options, rather than as a default completion callback. Add a public method `SetDefaultShellCompDirective(directive ShellCompDirective)` on `CompletionOptions` (package `cobra`) that records the given directive as the command's default.

The configured default directive is used when the completion engine cannot determine a more specific directive, for example for a flag that has no registered completion function. The configured default applies to the command and to its subcommands; a subcommand that configures its own default directive takes precedence over the value inherited from its parent. A directive determined from a more specific completion source, such as a registered flag completion function or a command's argument completion function, takes precedence over the configured default.
