Global StringArg + command: contextual help does not work
Hi. First of all, thanks for this excellent package. I hope it will be developed further because it shows an enormous potential.

With the following example code (simplified from docs):

```go
package main

import (
	"fmt"
	"os"
	cli "github.com/jawher/mow.cli"
)

var filename *string

func main() {
	app := cli.App("app", "description")

	filename = app.StringArg("FILENAME", "", "a string argument")

	app.Command("command1", "this should show with -h", command1)

	app.Run(os.Args)
}

func command1(cmd *cli.Cmd) {
	cmd.Action = func() {
		fmt.Printf("Hello from command1")
	}
}
```
I see the following behavior:
```
./app command1 --help
Error: incorrect usage

Usage: app FILENAME COMMAND [arg...]

description

Arguments:
  FILENAME     a string argument

Commands:
  command1     this should show with -h

Run 'app COMMAND --help' for more information on a command.
```
I would expect that the contextual help worked here, or is this the intended semantics? I couldn't find anything about this in the documentation, and the sole example combining top level parameters with commands used options instead of string arguments.

In case this is the intended semantics, where can I find the rationale in docs? And if not, and you are kind enough to point me around the code that deals with this part, I hope I can be able to submit a patch (I will at least give it a try).

Thanks!

### Additional contract requirements

Requesting help for a command with either `-h` or `--help` must print that command's
contextual help instead of an incorrect-usage error, even when a required argument of a
parent command (including the top-level app) has not been supplied. The contextual help
output contains the command path (the app name followed by the command names) and the
command's description.
