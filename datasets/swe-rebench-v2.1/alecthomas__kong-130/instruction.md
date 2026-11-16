command aliases (short commands)
Some flag handling packages allow shortcuts for commands.
I can do it my putting commands double in the parent struct like this, but it is kind of ugly:
```
type rootCmd struct {
	LongName    longNameCmd        `cmd:"" help:"Do something."`
	X1                 longNameCmd        `cmd:"" name:"ln"`
}
```

Is there a better way? Should I (try to) make a pull request for an extra tag, or to enable the short tag for commands as well?

### Additional contract requirements

- Command fields must support an `aliases` tag containing comma-separated names, such as `aliases:"alias1, alias2"`. Each alias must invoke its command, including nested commands; if an alias conflicts with an existing command name, the existing command must be selected.
