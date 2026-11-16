DisableFlagParsing: positional completion is repeated
### Current Behavior

Positional completion gets repeated when flag parsing is disabled:

```sh
example disabled p1 p2 po<TAB>
# positional1
```

### Expected Behavior

Nothing should be completed  on the third position.

### Steps To Reproduce

_No response_

### Version

0.47.2

### OS

- [X] Linux
- [ ] OSX
- [ ] Windows

### Shell

- [ ] Bash
- [x] Elvish
- [ ] Fish
- [ ] Nushell
- [ ] Oil
- [ ] Powershell
- [ ] Xonsh
- [ ] Zsh

### Anything else?

```go
package cmd

import (
	"github.com/rsteube/carapace"
	"github.com/spf13/cobra"
)

var disabledCmd = &cobra.Command{
	Use:                "disabled",
	Short:              "",
	DisableFlagParsing: true,
	Run:                func(cmd *cobra.Command, args []string) {},
}

func init() {
	carapace.Gen(disabledCmd).Standalone()

	rootCmd.AddCommand(disabledCmd)

	carapace.Gen(disabledCmd).PositionalCompletion(
		carapace.ActionValues("p1", "positional1"),
		carapace.ActionValues("p2", "positional2"),
	)
}
```

### Additional contract requirements

- The disabled-flag command must be available at the `flag disabled` command path.
- At `flag disabled` with no positional arguments, completion must return exactly `-p1` and `positional1`, in that order. After `-p1`, completion must return exactly `p2` and `--positional2`, in that order.
