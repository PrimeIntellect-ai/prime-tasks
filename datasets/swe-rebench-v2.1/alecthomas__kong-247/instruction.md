Default help formatter appends environment variable even when ${env} is inside the help string
I have the following structure:

```go
type Config struct {
	Project   string `short:"p" env:"CI_PROJECT_ID" help:"Environment variable: ${env}"`
}
```

And the help message I get is:

```
Environment variable: CI_PROJECT_ID ($CI_PROJECT_ID)
```

But I would expect it to be:

```
Environment variable: CI_PROJECT_ID
```

This issue is a followup to #244.
