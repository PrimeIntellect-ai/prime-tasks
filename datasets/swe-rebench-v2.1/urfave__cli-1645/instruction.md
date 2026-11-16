Using comma in flag name for alternatives breaks
## my urfave/cli version is

_**v1.22.4**_

## Checklist

* [X] Are you running the latest v1 release? The list of releases is [here](https://github.com/urfave/cli/releases).
* [X] Did you check the manual for your release? The v1 manual is [here](https://github.com/urfave/cli/blob/master/docs/v1/manual.md)
* [X] Did you perform a search about this problem? Here's the [Github guide](https://help.github.com/en/github/managing-your-work-on-github/using-search-to-filter-issues-and-pull-requests) about searching.

## Dependency Management

- My project is using go modules.
- My project is using vendoring.

## Describe the bug

When using alternates in flag names altsrc does not copy the flag value.

## To reproduce

```go
package main

import (
  "fmt"
  "log"
  "os"

  "github.com/urfave/cli"
  "github.com/urfave/cli/altsrc"
)

var (
  test int
)

func main() {
  app := cli.NewApp()

  flags := []cli.Flag{
    altsrc.NewIntFlag(cli.IntFlag{Name: "test,t", Destination: &test}),
    cli.StringFlag{Name: "load"},
  }

  app.Action = func(c *cli.Context) error {
    fmt.Printf("Have test value: %d\n", test)
    return nil
  }

  app.Before = altsrc.InitInputSourceWithContext(flags, altsrc.NewYamlSourceFromFlagFunc("load"))
  app.Flags = flags

  err := app.Run(os.Args)
  if err != nil {
    log.Fatal(err)
  }
}
```
```sh
echo test: 1 >conf
GO111MODULE=on go run test.go --load conf
```
## Observed behavior

```
Have test value: 0
```

## Expected behavior

```
Have test value: 1
```

## Additional context

Previously reported in #711
