MergeInConfig does not use extension as config type
### Preflight Checklist

- [x] I have searched the [issue tracker](https://www.github.com/spf13/viper/issues) for an issue that matches the one I want to file, without success.
- [x] I am not looking for support or already pursued the available [support channels](https://github.com/spf13/viper/issues/new/choose) without success.
- [x] I have checked the [troubleshooting guide](https://github.com/spf13/viper/blob/master/TROUBLESHOOTING.md) for my problem, without success.

### Viper Version

1.20.0

### Go Version

1.23

### Config Source

Files

### Format

YAML

### Repl.it link

https://replit.com/@graffic/MergeInConfig-error

### Code reproducing the issue

```go
package main

import (
	"github.com/spf13/viper"
)

func main() {
	v := viper.New()
	v.SetConfigFile("config.yaml")

	err := v.MergeInConfig()
	if err != nil {
		panic(err)
	}
}
```

### Expected Behavior

I would expect that [HIDDEN] so the call works.

### Actual Behavior

`MergeInConfig` already validates the configuration file extension, but [HIDDEN] and the call fails since there is none set.

### Steps To Reproduce

See repl.it link

### Additional Information

_No response_

### Additional contract requirements

- When a supported configuration file is selected by filename, `MergeInConfig` must use the file extension to determine its format and merge it successfully without requiring a configuration type to have been set separately.
