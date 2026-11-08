The default value of the empty default option is not printed correctly
```
package main

import (
	"fmt"
	"os"

	"github.com/jawher/mow.cli"
)

// Global options available to any of the commands
var filename *string

func main() {
	app := cli.App("vault", "Password Keeper")

	// Define our top-level global options
	filename = app.StringOpt("f file", "", "Path to safe")

	// Define our command structure for usage like this:
	app.Command("list", "list accounts", cmdList)
	app.Run(os.Args)
}

// Sample use: vault list OR vault config list
func cmdList(cmd *cli.Cmd) {
	cmd.Action = func() {
		fmt.Printf("list the contents of the safe here")
	}
}
```

The default value of filename is abc.txt which is specified when I execute the program.

```
 ~ ./vault -f abc.txt

Usage: vault [OPTIONS] COMMAND [arg...]

Password Keeper

Options:
  -f, --file   Path to safe (default "abc.txt")

Commands:
  list         list accounts

Run 'vault COMMAND --help' for more information on a command.
```

### Additional contract requirements

- When help is displayed after `-i=5` or with `INT1=25` set in the environment, the `-i, --int1` option line must include `(default 0)`.
- The default value shown in help is the value declared when the option or argument is defined, not a value later supplied by the user or the environment. In the sample above, `-f, --file` is declared with an empty default, so after `./vault -f abc.txt` its help line shows no `(default ...)` suffix.
