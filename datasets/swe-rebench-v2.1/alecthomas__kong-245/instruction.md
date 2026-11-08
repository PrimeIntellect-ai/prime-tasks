Specifying default overrides placeholder
I have:

```
var CLI struct {
	Changelog string `short:"f" placeholder:"PATH" default:"CHANGELOG.md" help:"Path to the changelog file to use."`
}
```

The help message is:

```
-f, --changelog="CHANGELOG.md"    Path to the changelog file to use.
```

I would expect it would be:

```
-f, --changelog=PATH    Path to the changelog file to use.
```

My plan is to show default value in the help message using variable interpolation.
