SkipFlagParsing is not working if there are Subcommands
## my urfave/cli version is

_**v1.22.5**_

## Checklist

* [x] Are you running the latest v1 release? The list of releases is [here](https://github.com/urfave/cli/releases).
* [x] Did you check the manual for your release? The v1 manual is [here](https://github.com/urfave/cli/blob/master/docs/v1/manual.md)
* [x] Did you perform a search about this problem? Here's the [Github guide](https://help.github.com/en/github/managing-your-work-on-github/using-search-to-filter-issues-and-pull-requests) about searching.

## Dependency Management

- My project is using go modules.

## Describe the bug

The options of `SkipFlagParsing: true` and `CustomHelpTemplate:"..."` are not working if there are Subcommands.

## To reproduce

```go
package main

import (
	"fmt"
	"os"

	"github.com/urfave/cli"
)

func main() {
	app := cli.NewApp()
	app.Name = "foo"
	app.Commands = []cli.Command{
		{
			Name:            "bar",
			SkipFlagParsing: true,
			Action: func(c *cli.Context) {
				fmt.Println(c.Args())
			},
			Subcommands: []cli.Command{{

				Name:            "barfoo",
				SkipFlagParsing: true,
				Action: func(c *cli.Context) {
					fmt.Println(c.Args())
				},
			},
			},
		},
	}

	app.Run(os.Args)
}
```

## Observed behavior
Run:

```
go build  -o skip && ./skip bar --a
```

Observed behavior:

```
Incorrect Usage. flag provided but not defined: -a

NAME:
   foo bar -

USAGE:
   foo bar command [command options] [arguments...]

COMMANDS:
   barfoo

OPTIONS:
   --help, -h  show help
```

## Expected behavior

The output should be:

```
[--a]
```

## Additional context

It works if I remove:

```
	Subcommands: []cli.Command{{

		Name:            "barfoo",
		SkipFlagParsing: true,
		Action: func(c *cli.Context) {
			fmt.Println(c.Args())
		},
	},
	},
```

### Additional contract requirements

When a command with subcommands has a `CustomHelpTemplate` configured, help rendered through the standard app-help path must use that template, including its literal text.
